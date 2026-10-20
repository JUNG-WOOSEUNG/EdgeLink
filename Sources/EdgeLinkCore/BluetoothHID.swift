import Foundation
import IOBluetooth

public protocol BluetoothHIDDelegate: AnyObject {
    func hid(_ hid: BluetoothHID, didChange state: BluetoothHID.State)
    /// 아이폰 쪽에서 연결해 올 때. false면 채널을 닫는다.
    func hid(_ hid: BluetoothHID, shouldAccept device: IOBluetoothDevice) -> Bool
    func hid(_ hid: BluetoothHID, didReceive leds: KeyboardLEDs)
    /// 쓰기 한 번이 50ms를 넘는 일이 3번 연속 생겼을 때. 앱은 Mac 조작으로 돌아와야 한다.
    func hidTransportStalled(_ hid: BluetoothHID)
}

public extension BluetoothHIDDelegate {
    func hid(_ hid: BluetoothHID, shouldAccept device: IOBluetoothDevice) -> Bool { true }
    func hid(_ hid: BluetoothHID, didReceive leds: KeyboardLEDs) {}
    func hidTransportStalled(_ hid: BluetoothHID) {}
}

/// Mac을 블루투스 HID 키보드·마우스로 보이게 한다.
///
/// - 설정·연결 메서드는 메인 스레드에서 부른다 (IOBluetooth 콜백이 메인 런루프로 온다).
/// - 보내기 메서드(`send`, `move`, `scroll`, `setButtons`)는 어느 스레드에서 불러도 된다.
///   쓰기는 전용 직렬 큐에서 하고, 마우스 움직임은 모아서 8ms마다 보낸다.
public final class BluetoothHID: NSObject {
    public static let controlPSM: BluetoothL2CAPPSM = 0x0011
    public static let interruptPSM: BluetoothL2CAPPSM = 0x0013
    /// 주변기기 · 키보드+포인팅 콤보, Limited Discoverable 서비스 비트
    public static let comboClassOfDevice: BluetoothClassOfDevice = 0x0025C0

    public enum State: Equatable {
        case idle
        case connecting(address: String)
        case connected(address: String)
        case disconnected(Reason)
    }

    public enum Reason: Equatable {
        case user
        case channelClosed
        case virtualCableUnplug
        case rejected
        case stalled
        case openFailed(stage: String, code: IOReturn)
    }

    public enum HIDError: Error, CustomStringConvertible {
        case bluetoothOff
        case sdpPublishFailed
        case invalidAddress(String)
        case openFailed(stage: String, code: IOReturn)

        public var description: String {
            switch self {
            case .bluetoothOff: return "Mac 블루투스가 꺼져 있어요"
            case .sdpPublishFailed: return "SDP 레코드 등록 실패"
            case .invalidAddress(let a): return "블루투스 주소 형식이 아니에요: \(a)"
            case let .openFailed(stage, code): return "\(stage) 열기 실패 (\(BluetoothHID.describe(code)))"
            }
        }
    }

    public weak var delegate: BluetoothHIDDelegate?
    public private(set) var state: State = .idle {
        didSet { if state != oldValue { delegate?.hid(self, didChange: state) } }
    }
    public private(set) var device: IOBluetoothDevice?
    public private(set) var serviceRecordHandle: BluetoothSDPServiceRecordHandle?

    /// 기본 기기 주소. 끊기면 이 주소로 다시 연결한다 (`autoReconnect`).
    public var defaultAddress: String?
    public var autoReconnect = false
    public private(set) var reconnectPolicy = ReconnectPolicy()

    private var serviceRecord: IOBluetoothSDPServiceRecord?
    private var control: IOBluetoothL2CAPChannel?
    private var interrupt: IOBluetoothL2CAPChannel?
    private var controlOpen = false
    private var interruptOpen = false
    private var openNotifications: [IOBluetoothUserNotification] = []
    private var userDisconnecting = false
    private var reconnectTimer: Timer?
    private var openTimer: Timer?
    private var openAttempt = 0

    /// 채널이 이 시간 안에 열리지 않으면 기본 연결부터 다시 맺는다 (`openRetries`번까지).
    public var openTimeout: TimeInterval = 30
    public var openRetries = 1

    // 아래는 writeQueue에서만 만진다
    private let writeQueue = DispatchQueue(label: "com.edgelink.hid.write", qos: .userInteractive)
    private var writeChannel: IOBluetoothL2CAPChannel?
    private var pending = PendingMotion()
    private var buttons: UInt8 = 0
    private var motionTimer: DispatchSourceTimer?
    private var slowWriteStreak = 0
    private var stats = WriteStats()

    public static let motionInterval: DispatchTimeInterval = .milliseconds(8)
    public static let slowWriteThreshold: TimeInterval = 0.050

    public override init() { super.init() }

    deinit {
        cancelReconnect()
        delegate = nil
        if device != nil { teardown(reason: .user) }
        stopListening()
        removeServiceRecord()
    }

    // MARK: 호스트(Mac)

    public struct HostInfo {
        public let name: String
        public let address: String
        public let classOfDevice: BluetoothClassOfDevice
        public let poweredOn: Bool
    }

    public static func hostInfo() -> HostInfo? {
        guard let host = IOBluetoothHostController.default() else { return nil }
        return HostInfo(name: host.nameAsString() ?? "",
                        address: host.addressAsString() ?? "",
                        classOfDevice: host.classOfDevice(),
                        poweredOn: host.powerState == kBluetoothHCIPowerStateON)
    }

    /// Mac이 잠시 동안 키보드(주변기기) 종류로 보이게 한다. 아이폰이 컴퓨터 종류를 HID로 받지 않을 때 시험용.
    @discardableResult
    public static func setClassOfDevice(_ cod: BluetoothClassOfDevice = comboClassOfDevice,
                                        for seconds: TimeInterval) -> IOReturn {
        guard let host = IOBluetoothHostController.default() else { return kIOReturnNotFound }
        return host.setClassOfDevice(cod, forTimeInterval: seconds)
    }

    // MARK: SDP

    public func publishServiceRecord(name: String = "EdgeLink") throws {
        guard serviceRecord == nil else { return }
        guard BluetoothHID.hostInfo()?.poweredOn == true else { throw HIDError.bluetoothOff }
        let dict = HIDServiceRecord.dictionary(serviceName: name)
        guard let record = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: dict) else {
            throw HIDError.sdpPublishFailed
        }
        serviceRecord = record
        var handle: BluetoothSDPServiceRecordHandle = 0
        if record.getHandle(&handle) == kIOReturnSuccess { serviceRecordHandle = handle }
        HIDLog.info("SDP 레코드 등록 (handle 0x\(String(serviceRecordHandle ?? 0, radix: 16)))")
    }

    public func removeServiceRecord() {
        guard let record = serviceRecord else { return }
        record.remove()
        serviceRecord = nil
        serviceRecordHandle = nil
        HIDLog.info("SDP 레코드 삭제")
    }

    // MARK: 연결 (Mac → 아이폰)

    public func connect(address: String) throws {
        guard BluetoothHID.hostInfo()?.poweredOn == true else { throw HIDError.bluetoothOff }
        guard let dev = IOBluetoothDevice(addressString: address) else { throw HIDError.invalidAddress(address) }
        cancelReconnect()
        if device != nil { teardown(reason: .user, reconnect: false) }
        userDisconnecting = false
        device = dev
        state = .connecting(address: dev.addressString ?? address)
        HIDLog.info("연결 시작 → \(dev.nameOrAddress)")
        openAttempt = 0
        // 기본 연결 단계에도 시간 제한: 아이폰 블루투스가 꺼져 있으면 응답이 없어 영영 기다렸다
        armOpenTimer(timeout: basebandTimeout)
        try startBaseband(dev)
    }

    /// 기본 연결(baseband)이 이 시간 안에 안 되면 다시 시도한다
    public var basebandTimeout: TimeInterval = 12

    /// 남아 있는 기본 연결 위에서는 채널이 열리지 않는 일이 있어서, 있으면 끊고 새로 맺는다.
    private func startBaseband(_ dev: IOBluetoothDevice) throws {
        if dev.isConnected() {
            HIDLog.info("남아 있던 기본 연결을 끊고 새로 연결해요")
            dev.closeConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.device === dev, case .connecting = self.state else { return }
                let r = dev.openConnection(self)
                if r != kIOReturnSuccess { self.fail(stage: "기기 연결", code: r) }
            }
            return
        }
        let r = dev.openConnection(self)
        guard r == kIOReturnSuccess else { throw fail(stage: "기기 연결", code: r) }
    }

    private func armOpenTimer(timeout: TimeInterval? = nil) {
        openTimer?.invalidate()
        let t = timeout ?? openTimeout
        openTimerSeconds = t
        openTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
            self?.openTimedOut()
        }
    }
    private var openTimerSeconds: TimeInterval = 0

    private func openTimedOut() {
        guard case .connecting = state, let dev = device else { return }
        HIDLog.warn("\(control == nil ? "기기 연결" : "채널")이 \(Int(openTimerSeconds))초 안에 되지 않았어요")
        let c = control, i = interrupt
        control = nil
        interrupt = nil
        controlOpen = false
        interruptOpen = false
        i?.close()
        c?.close()
        guard openAttempt < openRetries else {
            // 실패로 끝내면 자동 재연결이 15초 → 1분 → 5분으로 다시 시도한다
            fail(stage: "연결", code: kIOReturnTimeout)
            return
        }
        openAttempt += 1
        HIDLog.info("처음부터 다시 연결해요 (\(openAttempt)/\(openRetries))")
        dev.closeConnection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.device === dev, case .connecting = self.state else { return }
            self.armOpenTimer(timeout: self.basebandTimeout)
            let r = dev.openConnection(self)
            if r != kIOReturnSuccess { self.fail(stage: "기기 연결", code: r) }
        }
    }

    @objc public func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard case .connecting = state, device === self.device else { return }
        guard status == kIOReturnSuccess else {
            _ = fail(stage: "기기 연결", code: status)
            return
        }
        HIDLog.info("기기 연결됨 (baseband)")
        do { try openControlChannel() } catch { HIDLog.error("\(error)") }
    }

    private func openControlChannel() throws {
        guard let dev = device else { return }
        var ch: IOBluetoothL2CAPChannel?
        let r = dev.openL2CAPChannelAsync(&ch, withPSM: BluetoothHID.controlPSM, delegate: self)
        guard r == kIOReturnSuccess else { throw fail(stage: "제어 채널(0x11)", code: r) }
        control = ch
        armOpenTimer()
        HIDLog.info("제어 채널(0x11) 여는 중")
    }

    private func openInterruptChannel() {
        guard let dev = device else { return }
        var ch: IOBluetoothL2CAPChannel?
        let r = dev.openL2CAPChannelAsync(&ch, withPSM: BluetoothHID.interruptPSM, delegate: self)
        guard r == kIOReturnSuccess else {
            _ = fail(stage: "인터럽트 채널(0x13)", code: r)
            return
        }
        interrupt = ch
        HIDLog.info("인터럽트 채널(0x13) 여는 중")
    }

    @discardableResult
    private func fail(stage: String, code: IOReturn) -> HIDError {
        HIDLog.error("\(stage) 실패: \(BluetoothHID.describe(code))")
        if !userDisconnecting { teardown(reason: .openFailed(stage: stage, code: code)) }
        return .openFailed(stage: stage, code: code)
    }

    // MARK: 연결 받기 (아이폰 → Mac)

    public func listen() {
        guard openNotifications.isEmpty else { return }
        for psm in [BluetoothHID.controlPSM, BluetoothHID.interruptPSM] {
            if let n = IOBluetoothL2CAPChannel.register(forChannelOpenNotifications: self,
                                                         selector: #selector(channelOpened(_:channel:)),
                                                         withPSM: psm,
                                                         direction: kIOBluetoothUserNotificationChannelDirectionIncoming) {
                openNotifications.append(n)
            } else {
                HIDLog.error("PSM 0x\(String(psm, radix: 16)) 수신 등록 실패")
            }
        }
        HIDLog.info("아이폰의 연결을 기다려요 (PSM 0x11, 0x13)")
    }

    public func stopListening() {
        openNotifications.forEach { $0.unregister() }
        openNotifications = []
    }

    @objc private func channelOpened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        guard let dev = channel.device else { return }
        let psm = channel.psm
        HIDLog.info("들어온 채널 PSM 0x\(String(psm, radix: 16)) ← \(dev.nameOrAddress)")
        if isConnected {
            HIDLog.warn("이미 연결돼 있어서 새로 들어온 채널은 닫아요")
            channel.close()
            return
        }
        if let current = device, current.addressString != dev.addressString {
            HIDLog.warn("이미 다른 기기와 연결 중이라 닫아요")
            channel.close()
            return
        }
        if device == nil {
            guard delegate?.hid(self, shouldAccept: dev) ?? true else {
                HIDLog.warn("허용하지 않은 기기라 닫아요")
                channel.close()
                state = .disconnected(.rejected)
                return
            }
            device = dev
            userDisconnecting = false
            state = .connecting(address: dev.addressString ?? "")
        }
        channel.setDelegate(self)
        if psm == BluetoothHID.controlPSM { control = channel } else { interrupt = channel }
        channelDidOpen(channel)
    }

    // MARK: 끊기

    public func disconnect() {
        // 끊긴 뒤 예약된 재연결도 취소한다 (device가 nil이어도)
        cancelReconnect()
        guard device != nil else { return }
        userDisconnecting = true
        sendEmptyReports()
        waitForWrites(timeout: 0.2)  // 빈 리포트가 나간 뒤 닫는다 (전송이 막혀도 오래 기다리지 않음)
        teardown(reason: .user)
    }

    /// 채널을 닫는 중엔 큐에 남은 리포트를 버린다 (메인에서 바꾸고 쓰기 큐에서 읽음)
    private let acceptLock = NSLock()
    private var accepting = false
    private func setAccepting(_ v: Bool) { acceptLock.lock(); accepting = v; acceptLock.unlock() }
    private var isAccepting: Bool { acceptLock.lock(); defer { acceptLock.unlock() }; return accepting }

    /// 쓰기 큐가 비기를 최대 timeout초 기다린다. 메인 스레드가 블루투스 전송 지연에 묶이지 않게.
    @discardableResult
    private func waitForWrites(timeout: TimeInterval) -> Bool {
        let done = DispatchSemaphore(value: 0)
        writeQueue.async { done.signal() }
        return done.wait(timeout: .now() + timeout) == .success
    }

    private func teardown(reason: Reason, reconnect: Bool = true) {
        guard device != nil || control != nil || interrupt != nil else { return }
        openTimer?.invalidate()
        openTimer = nil
        // 큐에 남은 쓰기가 닫히는 채널로 가지 않게 먼저 막는다
        setAccepting(false)
        // 기다리지 않는다. 직렬 큐라 이후의 채널 열기보다 먼저 실행된다.
        writeQueue.async {
            self.motionTimer?.cancel()
            self.motionTimer = nil
            self.writeChannel = nil
            self.pending = PendingMotion()
            self.buttons = 0
            self.slowWriteStreak = 0
        }
        // HID 규격: 인터럽트 먼저, 그다음 제어
        let i = interrupt, c = control, d = device
        interrupt = nil
        control = nil
        controlOpen = false
        interruptOpen = false
        device = nil
        waitForWrites(timeout: 0.1)  // 지금 쓰는 중인 리포트가 끝나기를 잠깐 기다린 뒤 닫는다
        i?.close()
        c?.close()
        if reason == .user || reason == .virtualCableUnplug { d?.closeConnection() }
        state = .disconnected(reason)
        if reconnect, autoReconnect, !userDisconnecting, reason != .user, reason != .virtualCableUnplug, reason != .rejected,
           let address = defaultAddress ?? d?.addressString {
            scheduleReconnect(to: address)
        }
    }

    // MARK: 자동 재연결

    private func scheduleReconnect(to address: String) {
        cancelReconnect()
        let delay = reconnectPolicy.nextDelay()
        nextReconnectAt = Date().addingTimeInterval(delay)
        HIDLog.info("\(Int(delay))초 뒤 다시 연결")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.nextReconnectAt = nil
            guard self.device == nil else { return }
            do { try self.connect(address: address) } catch { HIDLog.error("재연결 실패: \(error)") }
        }
    }

    /// 다음 자동 재연결 예약 시각 (없으면 nil). 팝오버의 "1분 뒤에 다시 시도해요"에 쓴다.
    public private(set) var nextReconnectAt: Date?

    public func cancelReconnect() {
        nextReconnectAt = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: 보내기

    public var isConnected: Bool { if case .connected = state { return true } else { return false } }

    public func send(_ report: KeyboardReport) { enqueue(report.bytes, flushMotionFirst: true) }
    public func send(_ report: ConsumerReport) { enqueue(report.bytes, flushMotionFirst: true) }

    /// Consumer 키 한 번 누르고 떼기.
    public func tap(consumer usage: UInt16) {
        send(ConsumerReport(usage: usage))
        send(ConsumerReport(usage: 0))
    }

    /// 움직임은 모았다가 8ms마다 한 번에 보낸다.
    /// 마지막 움직임 전송이 8ms 넘게 지났으면 바로 보내고, 아니면 타이머가 보낸다.
    /// (타이머만 믿으면 절전 등으로 늦어질 때 움직임이 끊겨 보였음)
    public func move(dx: Int, dy: Int) {
        writeQueue.async {
            guard self.writeChannel != nil else { return }
            self.pending.dx += dx; self.pending.dy += dy
            let now = DispatchTime.now().uptimeNanoseconds
            if now &- self.lastMotionFlush >= 8_000_000 { self.flushMotion() }
        }
    }

    // writeQueue에서만
    private var lastMotionFlush: UInt64 = 0

    public func scroll(wheel: Int, pan: Int = 0) {
        writeQueue.async {
            guard self.writeChannel != nil else { return }
            self.pending.wheel += wheel; self.pending.pan += pan
        }
    }

    /// 버튼 상태를 바꾼다. 모인 움직임을 먼저 보내서 순서를 지킨다.
    public func setButtons(_ newButtons: UInt8) {
        writeQueue.async {
            self.flushMotion()
            self.buttons = newButtons
            self.write(MouseReport(buttons: newButtons).bytes)
        }
    }

    /// 키보드 리포트 여러 개를 간격을 두고 보낸다. 아이폰이 너무 붙은 신호를 놓치는 조합키(⌃Space 등)에 쓴다.
    public func send(_ reports: [KeyboardReport], gap: TimeInterval) {
        writeQueue.async {
            self.flushMotion()
            for (i, r) in reports.enumerated() {
                if i > 0 { usleep(useconds_t(gap * 1_000_000)) }
                self.write(r.bytes)
            }
        }
    }

    /// 버튼 하나를 누르고 바로 뗀다 (제스처 → 추가 버튼).
    /// 버튼을 hold초 동안 누르고 뗀다. 10ms로 짧게 누르면 아이폰 AssistiveTouch가 추가 버튼을 알아채지 못했다.
    /// 기다리는 동안 쓰기 큐를 막지 않아서 움직임은 계속 나간다.
    public func click(button: Int, hold: TimeInterval = 0.1) {
        guard (1...8).contains(button) else { return }
        let bit = UInt8(1) << UInt8(button - 1)
        writeQueue.async {
            self.flushMotion()
            self.buttons |= bit
            self.write(MouseReport(buttons: self.buttons).bytes)
        }
        writeQueue.asyncAfter(deadline: .now() + hold) {
            self.flushMotion()
            self.buttons &= ~bit
            self.write(MouseReport(buttons: self.buttons).bytes)
        }
    }

    /// 키보드·마우스·Consumer 빈 리포트. 연결 직후와 복귀·끊김 때 보낸다.
    public func sendEmptyReports() {
        writeQueue.async {
            self.pending = PendingMotion()
            self.buttons = 0
            self.write(KeyboardReport().bytes)
            self.write(MouseReport().bytes)
            self.write(ConsumerReport(usage: 0).bytes)
        }
    }

    /// 지금까지의 쓰기 시간 통계.
    /// 지금까지의 쓰기 시간 통계. 전송이 막혀 timeout 안에 못 읽으면 nil.
    public func writeStatistics(timeout: TimeInterval = 0.2) -> WriteStats? {
        var result = WriteStats()
        let done = DispatchSemaphore(value: 0)
        writeQueue.async { result = self.stats; done.signal() }
        return done.wait(timeout: .now() + timeout) == .success ? result : nil
    }
    public func resetWriteStatistics() { writeQueue.async { self.stats = WriteStats() } }

    private func enqueue(_ bytes: [UInt8], flushMotionFirst: Bool) {
        writeQueue.async {
            if flushMotionFirst { self.flushMotion() }
            self.write(bytes)
        }
    }

    // writeQueue에서만
    private func flushMotion() {
        guard !pending.isEmpty else { return }
        let reports = MouseReport.split(dx: pending.dx, dy: pending.dy, wheel: pending.wheel, pan: pending.pan, buttons: buttons)
        pending = PendingMotion()
        lastMotionFlush = DispatchTime.now().uptimeNanoseconds
        motionSends.tick()
        maxSplit = max(maxSplit, reports.count)
        for r in reports { write(r.bytes) }
    }

    // 움직임 끊김 진단 (writeQueue에서만)
    private var motionSends = GapMeter()
    private var maxSplit = 0
    private var maxWriteMs: Double = 0

    /// 움직임 전송 진단: 8ms 묶음 전송 간격, 한 번에 쪼갠 리포트 수 최대, 쓰기 한 번 최대 시간. 읽으면 비운다.
    public func takeMotionDiagnostics() -> (sends: GapMeter.Summary, maxSplit: Int, maxWriteMs: Double)? {
        var result: (GapMeter.Summary, Int, Double)?
        let done = DispatchSemaphore(value: 0)
        writeQueue.async {
            result = (self.motionSends.take(), self.maxSplit, self.maxWriteMs)
            self.maxSplit = 0
            self.maxWriteMs = 0
            done.signal()
        }
        guard done.wait(timeout: .now() + 0.1) == .success, let r = result else { return nil }
        return (sends: r.0, maxSplit: r.1, maxWriteMs: r.2)
    }

    // writeQueue에서만
    private func write(_ bytes: [UInt8]) {
        guard let channel = writeChannel, isAccepting else { return }
        var buf = bytes
        let start = DispatchTime.now().uptimeNanoseconds
        let r = buf.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        let elapsed = TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        stats.record(elapsed, ok: r == kIOReturnSuccess)
        maxWriteMs = max(maxWriteMs, elapsed * 1000)
        if r != kIOReturnSuccess {
            HIDLog.error("리포트 전송 실패: \(BluetoothHID.describe(r))")
        }
        if elapsed > BluetoothHID.slowWriteThreshold {
            slowWriteStreak += 1
            HIDLog.warn("쓰기 지연 \(Int(elapsed * 1000))ms (\(slowWriteStreak)번 연속)")
            if slowWriteStreak == 3 {
                DispatchQueue.main.async { self.delegate?.hidTransportStalled(self) }
            }
        } else {
            slowWriteStreak = 0
        }
    }

    // MARK: 채널 상태

    private func channelDidOpen(_ channel: IOBluetoothL2CAPChannel) {
        guard case .connecting = state else { return }
        if channel === control, !controlOpen {
            controlOpen = true
            HIDLog.info("제어 채널(0x11) 열림")
            // Mac이 연결하는 쪽이면 제어 채널 다음에 인터럽트 채널을 연다
            if interrupt == nil, !channel.isIncoming() { openInterruptChannel() }
        } else if channel === interrupt, !interruptOpen {
            interruptOpen = true
            HIDLog.info("인터럽트 채널(0x13) 열림")
        }
        guard controlOpen, interruptOpen, let i = interrupt else { return }
        writeQueue.async {
            self.writeChannel = i
            self.pending = PendingMotion()
            self.startMotionTimer()
        }
        setAccepting(true)
        reconnectPolicy.reset()
        let address = device?.addressString ?? ""
        openTimer?.invalidate()
        openTimer = nil
        state = .connected(address: address)
        HIDLog.info("HID 연결 성공 (\(device?.nameOrAddress ?? address), MTU \(i.outgoingMTU))")
        sendEmptyReports()
    }

    // writeQueue에서만
    private func startMotionTimer() {
        motionTimer?.cancel()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: writeQueue)
        t.schedule(deadline: .now() + BluetoothHID.motionInterval, repeating: BluetoothHID.motionInterval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.flushMotion() }
        t.resume()
        motionTimer = t
    }

    // MARK: 내부 도우미

    public static func describe(_ code: IOReturn) -> String {
        let known: [IOReturn: String] = [
            kIOReturnSuccess: "성공",
            kIOReturnNotPermitted: "허용되지 않음",
            kIOReturnNotPrivileged: "권한 없음",
            kIOReturnNoDevice: "기기 없음",
            kIOReturnNotOpen: "열려 있지 않음",
            kIOReturnTimeout: "시간 초과",
            kIOReturnBusy: "사용 중",
            kIOReturnNotFound: "찾을 수 없음",
            kIOReturnNotAttached: "연결 안 됨",
            kIOReturnError: "일반 오류",
            kIOReturnExclusiveAccess: "다른 곳에서 사용 중",
            kIOReturnAborted: "중단됨",
        ]
        let hexCode = String(format: "0x%08X", UInt32(bitPattern: code))
        return known[code].map { "\($0), \(hexCode)" } ?? hexCode
    }
}

// MARK: - IOBluetoothL2CAPChannelDelegate

extension BluetoothHID: IOBluetoothL2CAPChannelDelegate {
    public func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        guard let ch = l2capChannel, ch === control || ch === interrupt else { return }
        guard error == kIOReturnSuccess else {
            let stage = ch.psm == BluetoothHID.controlPSM ? "제어 채널(0x11)" : "인터럽트 채널(0x13)"
            _ = fail(stage: stage, code: error)
            return
        }
        channelDidOpen(ch)
    }

    public func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let ch = l2capChannel, let ptr = dataPointer, dataLength > 0 else { return }
        let bytes = Array(UnsafeRawBufferPointer(start: ptr, count: dataLength))
        if ch === control {
            HIDLog.debug("제어 메시지 받음: \(hex(bytes))")
            let result = HIDP.handleControl(bytes) { [weak self] body in self?.handleOutputReport(body) }
            switch result {
            case .reply(var reply):
                _ = reply.withUnsafeMutableBytes { ch.writeSync($0.baseAddress, length: UInt16($0.count)) }
            case .virtualCableUnplug:
                HIDLog.info("아이폰이 연결을 해제했어요 (Virtual Cable Unplug)")
                teardown(reason: .virtualCableUnplug)
            case .ignore:
                break
            }
        } else if ch === interrupt, bytes.first == HIDP.dataOutput {
            handleOutputReport(Array(bytes.dropFirst()))
        }
    }

    public func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        guard let ch = l2capChannel, ch === control || ch === interrupt else { return }
        HIDLog.info("채널 PSM 0x\(String(ch.psm, radix: 16)) 닫힘")
        guard !userDisconnecting, device != nil else { return }
        teardown(reason: .channelClosed)
    }

    private func handleOutputReport(_ body: [UInt8]) {
        guard let leds = KeyboardLEDs(outputReport: body) else { return }
        delegate?.hid(self, didReceive: leds)
    }
}

// MARK: - 보조 타입

struct PendingMotion {
    var dx = 0, dy = 0, wheel = 0, pan = 0
    var isEmpty: Bool { dx == 0 && dy == 0 && wheel == 0 && pan == 0 }
}

/// 재연결 간격: 15초 → 1분 → 5분 (이후 5분 유지).
public struct ReconnectPolicy {
    public static let delays: [TimeInterval] = [15, 60, 300]
    private var attempt = 0
    public init() {}
    public mutating func nextDelay() -> TimeInterval {
        defer { attempt += 1 }
        return ReconnectPolicy.delays[min(attempt, ReconnectPolicy.delays.count - 1)]
    }
    public mutating func reset() { attempt = 0 }
}

/// 리포트 쓰기 시간(writeSync 호출 ~ 하드웨어 전달) 통계.
public struct WriteStats {
    public private(set) var count = 0
    public private(set) var failures = 0
    public private(set) var total: TimeInterval = 0
    public private(set) var max: TimeInterval = 0
    private var samples: [TimeInterval] = []

    public init() {}

    mutating func record(_ t: TimeInterval, ok: Bool) {
        count += 1
        if !ok { failures += 1 }
        total += t
        max = Swift.max(max, t)
        if samples.count < 10_000 { samples.append(t) }
    }

    public var average: TimeInterval { count == 0 ? 0 : total / Double(count) }
    public var p95: TimeInterval {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }

    public var summary: String {
        String(format: "쓰기 %d회 (실패 %d) · 평균 %.2fms · p95 %.2fms · 최대 %.2fms",
               count, failures, average * 1000, p95 * 1000, max * 1000)
    }
}

extension IOBluetoothDevice {
    public var nameOrAddress: String {
        if let n = name, !n.isEmpty { return "\(n) (\(addressString ?? "?"))" }
        return addressString ?? "?"
    }
}
