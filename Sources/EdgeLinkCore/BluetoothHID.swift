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
        if dev.isConnected() {
            try openControlChannel()
        } else {
            let r = dev.openConnection(self)
            guard r == kIOReturnSuccess else { throw fail(stage: "기기 연결", code: r) }
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
        guard device != nil else { return }
        userDisconnecting = true
        cancelReconnect()
        sendEmptyReports()
        writeQueue.sync {}  // 빈 리포트가 나간 뒤 닫는다
        teardown(reason: .user)
    }

    private func teardown(reason: Reason, reconnect: Bool = true) {
        guard device != nil || control != nil || interrupt != nil else { return }
        writeQueue.sync {
            motionTimer?.cancel()
            motionTimer = nil
            writeChannel = nil
            pending = PendingMotion()
            buttons = 0
            slowWriteStreak = 0
        }
        // HID 규격: 인터럽트 먼저, 그다음 제어
        let i = interrupt, c = control, d = device
        interrupt = nil
        control = nil
        controlOpen = false
        interruptOpen = false
        device = nil
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
        HIDLog.info("\(Int(delay))초 뒤 다시 연결")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.device == nil else { return }
            do { try self.connect(address: address) } catch { HIDLog.error("재연결 실패: \(error)") }
        }
    }

    public func cancelReconnect() {
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
    public func move(dx: Int, dy: Int) {
        writeQueue.async {
            guard self.writeChannel != nil else { return }
            self.pending.dx += dx; self.pending.dy += dy
        }
    }

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

    /// 버튼 하나를 누르고 바로 뗀다 (제스처 → 추가 버튼).
    public func click(button: Int) {
        guard (1...8).contains(button) else { return }
        writeQueue.async {
            self.flushMotion()
            let bit = UInt8(1) << UInt8(button - 1)
            self.write(MouseReport(buttons: self.buttons | bit).bytes)
            usleep(10_000) // AssistiveTouch가 놓치지 않게 누름과 뗌 사이 10ms
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
    public func writeStatistics() -> WriteStats { writeQueue.sync { stats } }
    public func resetWriteStatistics() { writeQueue.sync { stats = WriteStats() } }

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
        for r in reports { write(r.bytes) }
    }

    // writeQueue에서만
    private func write(_ bytes: [UInt8]) {
        guard let channel = writeChannel else { return }
        var buf = bytes
        let start = DispatchTime.now().uptimeNanoseconds
        let r = buf.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        let elapsed = TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        stats.record(elapsed, ok: r == kIOReturnSuccess)
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
        writeQueue.sync {
            writeChannel = i
            pending = PendingMotion()
            startMotionTimer()
        }
        reconnectPolicy.reset()
        let address = device?.addressString ?? ""
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
