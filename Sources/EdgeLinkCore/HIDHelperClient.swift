import Foundation
import IOBluetooth

public protocol HIDHelperClientDelegate: AnyObject {
    func hid(_ hid: HIDHelperClient, didChange state: BluetoothHID.State)
    /// 허용하지 않은 기기가 연결해 와서 도우미가 닫았다 (받을지는 `acceptPolicy`로 도우미가 정한다)
    func hid(_ hid: HIDHelperClient, didRejectIncoming address: String, name: String)
    func hid(_ hid: HIDHelperClient, didReceive leds: KeyboardLEDs)
    /// 블루투스 쓰기가 막히거나 도우미가 응답하지 않을 때. 앱은 Mac 조작으로 돌아와야 한다.
    func hidTransportStalled(_ hid: HIDHelperClient)
    /// SDP 등록 실패처럼 상태로 나타나지 않는 오류
    func hid(_ hid: HIDHelperClient, didFail message: String)
}

public extension HIDHelperClientDelegate {
    func hid(_ hid: HIDHelperClient, didRejectIncoming address: String, name: String) {}
    func hid(_ hid: HIDHelperClient, didReceive leds: KeyboardLEDs) {}
    func hidTransportStalled(_ hid: HIDHelperClient) {}
    func hid(_ hid: HIDHelperClient, didFail message: String) {}
}

/// 도우미 프로세스 하나와의 연결. 실제로는 `ProcessHelperLink`, 테스트에선 가짜를 쓴다.
public protocol HelperLink: AnyObject {
    var pid: Int32 { get }
    /// 메시지 하나(길이 포함)를 보낸다. 막히지 않는다. 보내지 못했으면 false.
    @discardableResult func send(_ frame: [UInt8]) -> Bool
    /// 보내는 쪽을 닫는다 (도우미는 EOF를 받으면 정리하고 끝난다)
    func close()
    /// SIGTERM, 1초 안에 안 끝나면 SIGKILL
    func terminate()
    func waitForExit(timeout: TimeInterval) -> Bool
}

public struct HelperLinkHandlers {
    /// 읽기 스레드에서 불린다
    public var onEvent: (HelperEvent) -> Void
    /// 아무 스레드에서나 불린다
    public var onExit: (Int32) -> Void
    /// 도우미가 읽지 않아 보낼 메시지가 쌓였을 때 (아무 스레드)
    public var onBackpressure: () -> Void

    public init(onEvent: @escaping (HelperEvent) -> Void, onExit: @escaping (Int32) -> Void,
                onBackpressure: @escaping () -> Void = {}) {
        self.onEvent = onEvent
        self.onExit = onExit
        self.onBackpressure = onBackpressure
    }
}

public typealias HelperLauncher = (HelperLinkHandlers) throws -> HelperLink

/// 도우미가 갑자기 끝났을 때 다시 띄우기까지 기다리는 시간: 0.5초 → 2초 → 5초 → 15초 → 30초.
/// 1분 넘게 잘 돌았으면 처음부터 다시 센다.
public struct HelperRestartPolicy {
    public var delays: [TimeInterval]
    public var stableAfter: TimeInterval
    private var attempt = 0
    private var launchedAt: Date?

    public init(delays: [TimeInterval] = [0.5, 2, 5, 15, 30], stableAfter: TimeInterval = 60) {
        self.delays = delays
        self.stableAfter = stableAfter
    }

    public mutating func noteLaunched(at date: Date) { launchedAt = date }

    public mutating func nextDelay(now: Date) -> TimeInterval {
        if let l = launchedAt, now.timeIntervalSince(l) >= stableAfter { attempt = 0 }
        defer { attempt += 1 }
        return delays[min(attempt, delays.count - 1)]
    }
}

/// 앱 쪽에서 블루투스 HID를 맡은 도우미 프로세스(edgelink-hid)를 부리는 대리 객체.
/// `BluetoothHID`와 같은 모양이라 AppModel·InputRouter는 거의 그대로 쓴다.
///
/// 왜 따로 띄우나: 아이폰이 블루투스를 껐다 켠 뒤 재연결이 실패하는 동안 IOBluetooth가 메인 스레드에서
/// 채널 열기를 동기로 기다려 메뉴바가 4~5초마다 몇 초씩 멈췄다 (콜백이 메인 큐로 와서 앱 코드로는 막을 수 없음).
/// 도우미 메인 스레드가 멈춰도 앱 UI·입력 감시·Mac으로 돌아오기는 멈추지 않는다.
///
/// - 설정·연결 메서드와 `state`는 `queue`(앱에선 메인)에서 쓴다. 대리자도 거기서 불린다.
/// - 보내기 메서드(`send`, `move`, `scroll`, `setButtons`, `click`…)는 어느 스레드에서 불러도 되고 막히지 않는다.
/// - 도우미가 끝나거나 하트비트가 끊기면 Mac 조작으로 돌아오게 알리고(상태 `.disconnected(.helperLost)`),
///   간격을 두고 다시 띄운 뒤 설정을 다시 보내고 기본 기기에 다시 연결한다.
public final class HIDHelperClient {
    public struct AcceptPolicy: Equatable {
        public var address: String?
        public var acceptAll: Bool
        public init(address: String? = nil, acceptAll: Bool = false) {
            self.address = address
            self.acceptAll = acceptAll
        }
    }

    public struct Timing {
        /// 이만큼 아무 소식이 없으면 도우미를 죽이고 다시 띄운다. 실기기에서 IOBluetooth가 3~10초 멈춰서 넉넉히.
        public var heartbeatTimeout: TimeInterval = 20
        /// 연결된 채로 이만큼 소식이 없으면 Mac 조작으로 돌아오게 한다 (도우미는 아직 그대로)
        public var silentStall: TimeInterval = 5
        public var watchInterval: TimeInterval = 1
        /// 채널 거절 때문에 새로 띄우는 것은 이 간격에 한 번까지
        public var freshRestartMinInterval: TimeInterval = 30
        public var freshRestartDelay: TimeInterval = 1
        public var restart = HelperRestartPolicy()
        public init() {}
    }

    public weak var delegate: HIDHelperClientDelegate?
    public private(set) var state: BluetoothHID.State = .idle
    public var isConnected: Bool { if case .connected = state { return true } else { return false } }
    /// 다음 자동 재연결 예약 시각 (팝오버의 "1분 뒤에 다시 시도해요")
    public private(set) var nextReconnectAt: Date?

    public var defaultAddress: String? {
        didSet { if defaultAddress != oldValue { sendNow(.setDefaultAddress(defaultAddress)) } }
    }
    public var autoReconnect = false {
        didSet { if autoReconnect != oldValue { sendNow(.setAutoReconnect(autoReconnect)) } }
    }
    public var acceptPolicy = AcceptPolicy() {
        didSet { if acceptPolicy != oldValue { sendNow(.setAcceptPolicy(address: acceptPolicy.address, acceptAll: acceptPolicy.acceptAll)) } }
    }

    /// Mac 블루투스 전원 (앱 프로세스에서 바로 읽는다. 테스트에선 바꿔 끼운다)
    public var bluetoothPoweredOn: () -> Bool = { BluetoothHID.hostInfo()?.poweredOn == true }

    /// 지금 도우미의 pid (없으면 nil)
    public var helperPID: Int32? { currentLink()?.pid }
    /// 도우미를 띄운 횟수 (테스트·로그용)
    public private(set) var launchCount = 0

    private let launcher: HelperLauncher
    private let queue: DispatchQueue
    private var timing: Timing

    private let linkLock = NSLock()
    private var link: HelperLink?   // linkLock

    // 아래는 queue에서만
    private var generation = 0
    private var serviceName: String?
    private var listening = false
    /// 다시 띄운 뒤 연결할 기기 (직접 끊거나 아이폰이 해제하면 nil)
    private var wantedAddress: String?
    /// 도우미가 없을 때 connect가 불렸으면 띄우자마자 연결한다
    private var connectOnLaunch = false
    private var restartScheduled = false
    private var lastFreshRestart: Date?
    /// 마지막으로 연결된 뒤 연결 시도가 실패한 횟수. 한 번 끊긴 뒤 같은 도우미로는 다시 붙지 않고
    /// 새로 띄우면 바로 붙는 일이 실기기에서 거듭 있었다(블루투스 껐다 켜기, 자리 옮겨 끊긴 뒤).
    private var failuresSinceConnected = 0
    private var shuttingDown = false
    private var silentReported = false
    private var watchTimer: DispatchSourceTimer?

    // 마지막으로 도우미 소식을 들은 때 (읽기 스레드가 바꾼다). 앱 메인이 바빠도 정확하게 재려고 따로 둔다.
    private let heardLock = NSLock()
    private var lastHeard = DispatchTime.now()

    // 응답을 기다리는 요청 (flush, 진단, ping)
    private final class Waiter {
        let done = DispatchSemaphore(value: 0)
        var ok = false
        var diagnostics: MotionDiagnostics?
    }
    private let waitLock = NSLock()
    private var waiters: [UInt32: Waiter] = [:]
    private var nextSeq: UInt32 = 0

    public init(launcher: @escaping HelperLauncher, queue: DispatchQueue = .main, timing: Timing = Timing()) {
        self.launcher = launcher
        self.queue = queue
        self.timing = timing
    }

    deinit {
        watchTimer?.cancel()
        currentLink()?.terminate()
    }

    // MARK: 도우미 위치

    /// 앱 번들의 Contents/MacOS/edgelink-hid. `swift build`로 만든 실행 파일 옆에 있어도 찾는다.
    public static var bundledHelperURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "edgelink-hid") { return url }
        let beside = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("edgelink-hid")
        return FileManager.default.isExecutableFile(atPath: beside.path) ? beside : nil
    }

    public static func processLauncher(executable: URL?) -> HelperLauncher {
        return { handlers in
            guard let executable else { throw HelperLaunchError.notFound }
            return try ProcessHelperLink(executable: executable, handlers: handlers)
        }
    }

    public enum HelperLaunchError: Error, CustomStringConvertible {
        case notFound
        public var description: String { "블루투스 도우미(edgelink-hid)를 찾지 못했어요" }
    }

    // MARK: SDP · 연결 받기

    /// 블루투스 일 없이 도우미만 띄운다 (이미 떠 있으면 그대로). 보통은 publish·listen·connect가 알아서 띄운다.
    public func startHelper() { launchIfNeeded() }

    /// SDP 등록. Mac 블루투스가 꺼져 있으면 바로 던지고, 등록 실패는 `didFail`로 알린다.
    public func publishServiceRecord(name: String = "EdgeLink") throws {
        guard bluetoothPoweredOn() else { throw BluetoothHID.HIDError.bluetoothOff }
        serviceName = name
        launchIfNeeded()
        sendNow(.publish(name: name))
    }

    public func removeServiceRecord() {
        serviceName = nil
        sendNow(.unpublish)
    }

    public func listen() {
        listening = true
        launchIfNeeded()
        sendNow(.listen)
    }

    public func stopListening() {
        listening = false
        sendNow(.stopListening)
    }

    // MARK: 연결 (Mac → 아이폰)

    public func connect(address: String) throws {
        guard bluetoothPoweredOn() else { throw BluetoothHID.HIDError.bluetoothOff }
        guard Self.isValidAddress(address) else { throw BluetoothHID.HIDError.invalidAddress(address) }
        wantedAddress = address
        nextReconnectAt = nil
        // 실패한 뒤 직접 다시 연결하면 도우미부터 새로 띄운다 (같은 도우미로는 다시 붙지 않던 일이 있었다)
        if failuresSinceConnected > 0, let old = takeLink() {
            generation += 1
            old.terminate()
            failWaiters()
            lastFreshRestart = Date()
            connectOnLaunch = true
            HIDLog.info("연결이 실패한 뒤라 블루투스 도우미를 새로 띄우고 연결해요")
            setState(.connecting(address: address))
            scheduleLaunch(after: timing.freshRestartDelay)
            return
        }
        if currentLink() == nil, restartScheduled {
            connectOnLaunch = true   // 도우미가 다시 뜨면 바로 연결
        } else {
            launchIfNeeded()
            sendNow(.connect(address: address))
        }
        setState(.connecting(address: address))
    }

    public func disconnect() {
        wantedAddress = nil
        connectOnLaunch = false
        nextReconnectAt = nil
        sendNow(.disconnect)
    }

    public func cancelReconnect() {
        nextReconnectAt = nil
        sendNow(.cancelReconnect)
    }

    /// 사용자가 직접 다시 연결하면 재연결 간격을 처음(15초)부터 다시 센다
    public func resetReconnectPolicy() { sendNow(.resetReconnectPolicy) }

    /// 앱을 끝낼 때. 끊고 도우미가 끝나기를 잠깐 기다린다.
    public func shutdown(timeout: TimeInterval = 0.5) {
        shuttingDown = true
        watchTimer?.cancel()
        watchTimer = nil
        guard let l = takeLink() else { return }
        generation += 1
        l.send(HelperProtocol.frame(HelperCommand.shutdown.encode()))
        l.close()
        if !l.waitForExit(timeout: timeout) { l.terminate() }
        failWaiters()
    }

    static func isValidAddress(_ s: String) -> Bool {
        s.range(of: #"^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$"#, options: .regularExpression) != nil
    }

    // MARK: 보내기 (아무 스레드)

    public func send(_ report: KeyboardReport) { sendNow(.keyboard(report)) }
    public func send(_ report: ConsumerReport) { sendNow(.consumer(report.usage)) }

    /// Consumer 키 한 번 누르고 떼기.
    public func tap(consumer usage: UInt16) {
        send(ConsumerReport(usage: usage))
        send(ConsumerReport(usage: 0))
    }

    public func move(dx: Int, dy: Int) { sendNow(.move(dx: Int32(clamping: dx), dy: Int32(clamping: dy))) }
    public func scroll(wheel: Int, pan: Int = 0) { sendNow(.scroll(wheel: Int32(clamping: wheel), pan: Int32(clamping: pan))) }
    public func setButtons(_ buttons: UInt8) { sendNow(.buttons(buttons)) }

    /// 키보드 리포트 여러 개를 간격을 두고 보낸다 (간격은 도우미가 지킨다)
    public func send(_ reports: [KeyboardReport], gap: TimeInterval) {
        sendNow(.keyboardSequence(reports, gapMs: UInt16(clamping: Int((gap * 1000).rounded()))))
    }

    public func click(button: Int, hold: TimeInterval = 0.1) {
        guard (1...8).contains(button) else { return }
        sendNow(.click(button: UInt8(button), holdMs: UInt16(clamping: Int((hold * 1000).rounded()))))
    }

    public func sendEmptyReports() { sendNow(.emptyReports) }

    /// 앞에서 보낸 리포트가 실제로 나갈 때까지 최대 timeout초 기다린다. 도우미가 없거나 늦으면 false.
    @discardableResult
    public func flushWrites(timeout: TimeInterval = 0.2) -> Bool {
        request(timeout: timeout) { .flush($0) }?.ok ?? false
    }

    /// 움직임 전송 진단. 읽으면 도우미 쪽 값을 비운다.
    public func takeMotionDiagnostics(timeout: TimeInterval = 0.1) -> MotionDiagnostics? {
        request(timeout: timeout) { .motionDiagnostics($0) }?.diagnostics
    }

    /// 도우미 메인 스레드가 답하는지 (상태 확인·테스트용). 메인 큐에서 부르면 그동안 막히니 짧게.
    public func ping(timeout: TimeInterval = 1) -> Bool {
        request(timeout: timeout) { .ping($0) }?.ok ?? false
    }

    // MARK: 내부: 보내기

    private func currentLink() -> HelperLink? {
        linkLock.lock(); defer { linkLock.unlock() }
        return link
    }

    private func setLink(_ l: HelperLink?) {
        linkLock.lock(); link = l; linkLock.unlock()
    }

    private func takeLink() -> HelperLink? {
        linkLock.lock(); defer { linkLock.unlock() }
        let l = link
        link = nil
        return l
    }

    @discardableResult
    private func sendNow(_ cmd: HelperCommand) -> Bool {
        guard let l = currentLink() else { return false }
        return l.send(HelperProtocol.frame(cmd.encode()))
    }

    private func request(timeout: TimeInterval, _ make: (UInt32) -> HelperCommand) -> Waiter? {
        guard currentLink() != nil else { return nil }
        let w = Waiter()
        waitLock.lock()
        nextSeq &+= 1
        let seq = nextSeq
        waiters[seq] = w
        waitLock.unlock()
        let sent = sendNow(make(seq))
        let answered = sent && w.done.wait(timeout: .now() + timeout) == .success
        waitLock.lock()
        waiters[seq] = nil
        waitLock.unlock()
        return answered ? w : nil
    }

    // 읽기 스레드
    private func resolve(_ seq: UInt32, _ fill: (Waiter) -> Void) {
        waitLock.lock()
        let w = waiters.removeValue(forKey: seq)
        waitLock.unlock()
        guard let w else { return }
        fill(w)
        w.done.signal()
    }

    private func failWaiters() {
        waitLock.lock()
        let all = waiters.values
        waiters = [:]
        waitLock.unlock()
        all.forEach { $0.done.signal() }
    }

    // MARK: 내부: 띄우기 · 감시

    private func launchIfNeeded() {
        guard currentLink() == nil, !restartScheduled, !shuttingDown else { return }
        launch(reconnect: false)
    }

    /// 도우미를 띄우고 지금 설정을 처음부터 다시 보낸다 (queue)
    private func launch(reconnect: Bool) {
        generation += 1
        let gen = generation
        let handlers = HelperLinkHandlers(
            onEvent: { [weak self] ev in self?.received(ev, gen: gen) },
            onExit: { [weak self] status in
                guard let self else { return }
                self.queue.async { self.exited(status: status, gen: gen) }
            },
            onBackpressure: { [weak self] in
                guard let self else { return }
                self.queue.async {
                    guard gen == self.generation else { return }
                    HIDLog.warn("블루투스 도우미가 메시지를 읽지 않아 밀려요")
                    self.delegate?.hidTransportStalled(self)
                }
            })
        let l: HelperLink
        do { l = try launcher(handlers) } catch {
            HIDLog.error("블루투스 도우미를 띄우지 못했어요: \(error)")
            scheduleLaunch(after: timing.restart.nextDelay(now: Date()))
            return
        }
        setLink(l)
        launchCount += 1
        timing.restart.noteLaunched(at: Date())
        markHeard()
        silentReported = false
        startWatch()

        // 설정 다시 보내기: 받기 규칙과 기본 주소를 SDP·연결 받기보다 먼저
        sendNow(.setAutoReconnect(autoReconnect))
        sendNow(.setDefaultAddress(defaultAddress))
        sendNow(.setAcceptPolicy(address: acceptPolicy.address, acceptAll: acceptPolicy.acceptAll))
        if let name = serviceName { sendNow(.publish(name: name)) }
        if listening { sendNow(.listen) }
        if let a = wantedAddress, connectOnLaunch || (reconnect && autoReconnect) {
            HIDLog.info("새 블루투스 도우미로 다시 연결해요")
            sendNow(.connect(address: a))
            setState(.connecting(address: a))
        }
        connectOnLaunch = false
    }

    private func scheduleLaunch(after delay: TimeInterval) {
        guard !restartScheduled, !shuttingDown else { return }
        restartScheduled = true
        HIDLog.info(String(format: "%.1f초 뒤 블루투스 도우미를 다시 띄워요", delay))
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.restartScheduled = false
            guard !self.shuttingDown, self.currentLink() == nil else { return }
            self.launch(reconnect: true)
        }
    }

    /// 도우미를 잃었다: 지금 것은 버리고(kill이면 죽이고) 연결 상태를 끊김으로 알린 뒤 다시 띄운다
    private func helperLost(_ why: String, kill: Bool, delay: TimeInterval? = nil) {
        let old = takeLink()
        generation += 1   // 예전 도우미가 늦게 보내는 소식은 버린다
        if kill { old?.terminate() }
        failWaiters()
        HIDLog.warn(why)
        nextReconnectAt = nil
        switch state {
        case .connected, .connecting: setState(.disconnected(.helperLost))
        default: break
        }
        guard !shuttingDown else { return }
        scheduleLaunch(after: delay ?? timing.restart.nextDelay(now: Date()))
    }

    private func exited(status: Int32, gen: Int) {
        guard gen == generation else { return }
        helperLost("블루투스 도우미가 끝났어요 (코드 \(status))", kill: false)
    }

    private func startWatch() {
        guard watchTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + timing.watchInterval, repeating: timing.watchInterval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.watch() }
        t.resume()
        watchTimer = t
    }

    private func watch() {
        guard currentLink() != nil else { return }
        heardLock.lock()
        let silent = Double(DispatchTime.now().uptimeNanoseconds &- lastHeard.uptimeNanoseconds) / 1e9
        heardLock.unlock()
        if silent > timing.heartbeatTimeout {
            helperLost("블루투스 도우미가 \(Int(silent))초 동안 응답하지 않아 다시 띄워요", kill: true)
            return
        }
        if silent > timing.silentStall, !silentReported {
            silentReported = true
            HIDLog.warn("블루투스 도우미 응답이 \(Int(silent))초째 없어요")
            if isConnected { delegate?.hidTransportStalled(self) }
        }
    }

    private func markHeard() {
        heardLock.lock(); lastHeard = .now(); heardLock.unlock()
    }

    // MARK: 내부: 받기

    // 읽기 스레드
    private func received(_ ev: HelperEvent, gen: Int) {
        markHeard()
        switch ev {
        case .pong(let s): resolve(s) { $0.ok = true }
        case let .flushed(s, ok): resolve(s) { $0.ok = ok }
        case let .motionDiagnostics(s, d): resolve(s) { $0.ok = d != nil; $0.diagnostics = d }
        case let .log(level, message):
            // 같은 로그 파일·연결 로그 창에 남긴다 (주소 뒷자리 가리기는 HIDLog가 한다)
            HIDLog.write(level, message)
        default:
            queue.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.handle(ev)
            }
        }
    }

    // queue
    private func handle(_ ev: HelperEvent) {
        switch ev {
        case let .hello(pid, version):
            HIDLog.info("블루투스 도우미 시작 (pid \(pid))")
            if version != HelperProtocol.version {
                HIDLog.error("블루투스 도우미 버전이 앱과 달라요 (\(version) ≠ \(HelperProtocol.version))")
            }
        case .heartbeat:
            silentReported = false
        case .state(let s):
            switch s {
            case .connected(let a):
                wantedAddress = a
                failuresSinceConnected = 0
            case .disconnected(.user), .disconnected(.virtualCableUnplug): wantedAddress = nil
            case .disconnected(.openFailed):
                failuresSinceConnected += 1
            default: break
            }
            setState(s)
            // 자동 재연결이 두 번 연달아 실패하면 다음 시도는 새 도우미로 (30초에 한 번까지)
            if case .disconnected(.openFailed) = s, failuresSinceConnected >= 2, failuresSinceConnected % 2 == 0 {
                freshRestart()
            }
        case .reconnectScheduled(let seconds):
            nextReconnectAt = seconds.map { Date().addingTimeInterval($0) }
        case let .incomingRejected(address, name):
            delegate?.hid(self, didRejectIncoming: address, name: name)
        case .leds(let raw):
            delegate?.hid(self, didReceive: KeyboardLEDs(rawValue: raw))
        case .stalled:
            delegate?.hidTransportStalled(self)
        case .needsFreshProcess:
            freshRestart()
        case .failure(let message):
            // 도우미가 연결을 시작하지도 못했으면(블루투스 꺼짐 등) "연결 중"에 머물지 않게
            if case .connecting = state { setState(.idle) }
            delegate?.hid(self, didFail: message)
        case .pong, .flushed, .motionDiagnostics, .log:
            break  // 읽기 스레드에서 처리함
        }
    }

    /// 한 번 연결됐던 기기가 채널을 계속 거절할 때: 도우미만 새로 띄워 IOBluetooth 상태를 비운다.
    /// (전엔 앱 전체를 다시 띄웠다. 30초에 한 번까지)
    private func freshRestart() {
        let now = Date()
        if let last = lastFreshRestart, now.timeIntervalSince(last) < timing.freshRestartMinInterval {
            HIDLog.warn("\(Int(timing.freshRestartMinInterval))초 안에 이미 다시 띄웠어서 이번엔 그대로 둬요")
            return
        }
        lastFreshRestart = now
        if wantedAddress == nil { wantedAddress = defaultAddress }
        connectOnLaunch = wantedAddress != nil
        helperLost("블루투스 도우미를 새로 띄워 블루투스 상태를 비워요", kill: true, delay: timing.freshRestartDelay)
    }

    private func setState(_ s: BluetoothHID.State) {
        guard s != state else { return }
        state = s
        delegate?.hid(self, didChange: s)
    }
}

// MARK: - 실제 프로세스

/// `Process`로 띄운 도우미와 stdin/stdout 파이프로 주고받는다.
///
/// 보내기는 논블로킹이다. 입력 감시 스레드에서 바로 부르기 때문에, 도우미가 멈춰 파이프가 차도
/// 기다리지 않는다. 다 못 쓴 나머지는 모아 두었다가 파이프가 비면 이어 쓴다(메시지가 중간에 잘리지 않게).
/// 모인 것이 `pendingLimit`를 넘으면 새 메시지는 버리고 `onBackpressure`로 알린다.
public final class ProcessHelperLink: HelperLink {
    public let pid: Int32
    public static let pendingLimit = 32 * 1024

    private let process: Process
    private let toHelper = Pipe()
    private let fromHelper = Pipe()
    private let writeFD: Int32
    private let handlers: HelperLinkHandlers

    private let lock = NSLock()
    private var pending: [UInt8] = []   // lock
    private var closed = false          // lock
    private var backpressureReported = false
    private let drainQueue = DispatchQueue(label: "com.edgelink.helper.out", qos: .userInteractive)
    private var source: DispatchSourceWrite?
    private var sourceRunning = false

    public init(executable: URL, arguments: [String] = [], handlers: HelperLinkHandlers) throws {
        self.handlers = handlers
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.standardInput = toHelper
        p.standardOutput = fromHelper
        // stderr는 앱 것을 그대로 쓴다 (터미널에서 띄웠을 때 보이게)
        p.terminationHandler = { handlers.onExit($0.terminationStatus) }
        try p.run()
        process = p
        pid = p.processIdentifier
        // 도우미 쪽 끝은 앱에서 닫아야 도우미가 끝났을 때 EOF가 온다
        try? toHelper.fileHandleForReading.close()
        try? fromHelper.fileHandleForWriting.close()

        writeFD = toHelper.fileHandleForWriting.fileDescriptor
        _ = fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(writeFD, F_SETNOSIGPIPE, 1)   // 도우미가 죽은 뒤 써도 앱이 SIGPIPE로 죽지 않게

        let readHandle = fromHelper.fileHandleForReading
        let t = Thread {
            Self.readLoop(fd: readHandle.fileDescriptor, handlers: handlers)
            _ = readHandle   // 읽는 동안 파일 핸들(과 fd)을 붙잡아 둔다
        }
        t.name = "EdgeLink 도우미 읽기"
        t.qualityOfService = .userInteractive
        t.start()
    }

    private static func readLoop(fd: Int32, handlers: HelperLinkHandlers) {
        var decoder = HelperFrameDecoder()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return }
            for body in decoder.append(Array(buf[0..<n])) {
                if let ev = HelperEvent.decode(body) { handlers.onEvent(ev) }
            }
            if decoder.broken {
                HIDLog.error("블루투스 도우미가 보낸 메시지가 깨졌어요")
                return
            }
        }
    }

    @discardableResult
    public func send(_ frame: [UInt8]) -> Bool {
        lock.lock()
        guard !closed else { lock.unlock(); return false }
        if pending.isEmpty {
            let n = writeSome(frame[...])
            if n == frame.count { lock.unlock(); return true }
            if n < 0 { closed = true; lock.unlock(); return false }   // 도우미가 끝남 (EPIPE)
            pending.append(contentsOf: frame[n...])
            startDrain()
            lock.unlock()
            return true
        }
        guard pending.count + frame.count <= Self.pendingLimit else {
            let report = !backpressureReported
            backpressureReported = true
            lock.unlock()
            if report { handlers.onBackpressure() }
            return false
        }
        pending.append(contentsOf: frame)
        lock.unlock()
        return true
    }

    /// 쓸 수 있는 만큼 쓴다. 쓴 바이트 수, 파이프가 닫혔으면 -1 (lock 안에서)
    private func writeSome(_ bytes: ArraySlice<UInt8>) -> Int {
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                write(writeFD, raw.baseAddress! + done, raw.count - done)
            }
            if n > 0 { done += n; continue }
            if n < 0, errno == EINTR { continue }
            if n < 0, errno == EAGAIN { return done }
            return -1
        }
        return done
    }

    // lock 안에서
    private func startDrain() {
        if source == nil {
            let s = DispatchSource.makeWriteSource(fileDescriptor: writeFD, queue: drainQueue)
            s.setEventHandler { [weak self] in self?.drain() }
            source = s
        }
        if !sourceRunning { sourceRunning = true; source?.resume() }
    }

    private func drain() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        let n = writeSome(pending[...])
        if n < 0 { closed = true; pending = []; return }
        pending.removeFirst(n)
        if pending.isEmpty {
            backpressureReported = false
            if sourceRunning { sourceRunning = false; source?.suspend() }
        }
    }

    public func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        pending = []
        let s = source
        let running = sourceRunning
        source = nil
        sourceRunning = false
        lock.unlock()
        if let s {
            s.cancel()
            if !running { s.resume() }   // 멈춘 소스는 다시 켜야 취소가 끝난다
        }
        try? toHelper.fileHandleForWriting.close()
    }

    public func terminate() {
        close()
        guard process.isRunning else { return }
        process.terminate()
        let pid = self.pid
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }

    public func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline { return false }
            usleep(10_000)
        }
        return true
    }
}
