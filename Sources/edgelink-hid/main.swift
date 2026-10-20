import Foundation
import IOBluetooth
import EdgeLinkCore

// EdgeLink 블루투스 도우미. 앱(EdgeLink.app)이 띄우고 stdin/stdout으로 짧은 바이너리 메시지를 주고받는다
// (형식은 EdgeLinkCore/HelperMessages.swift).
//
// 블루투스 HID(SDP·L2CAP 채널·리포트 쓰기)를 이 프로세스가 다 맡는다. IOBluetooth가 메인 스레드에서
// 채널 열기를 몇 초씩 기다려도 앱의 메뉴바·입력 감시는 멈추지 않고, 꼬이면 앱이 이 프로세스만 다시 띄운다.
// stdin이 닫히면(앱이 끝나거나 죽으면) 연결을 끊고 끝난다.

final class HelperServer: NSObject, BluetoothHIDDelegate {
    private let hid = BluetoothHID()
    private let outFD: Int32
    private let outLock = NSLock()
    private var heartbeat: Timer?
    private let parentPID = getppid()

    // 메인에서만
    private var acceptAddress: String?
    private var acceptAll = false

    init(outFD: Int32) {
        self.outFD = outFD
        super.init()
    }

    func start() {
        // 로그는 앱으로 보내서 앱이 같은 파일·연결 로그 창에 남긴다
        HIDLog.echo = nil
        HIDLog.systemLog = false
        HIDLog.forward = { [weak self] level, message in self?.emit(.log(level: level, message: message)) }
        hid.delegate = self
        emit(.hello(pid: getpid(), version: HelperProtocol.version))
        // 하트비트는 메인 스레드에서: IOBluetooth가 메인을 오래 붙잡으면 앱이 알아챈다
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 앱이 죽었는데 stdin EOF를 못 받은 경우를 대비해 부모도 확인한다
            if getppid() != self.parentPID { self.finish() }
            self.emit(.heartbeat)
        }
        let t = Thread { [weak self] in self?.readLoop() }
        t.name = "EdgeLink 도우미 명령 읽기"
        t.qualityOfService = .userInteractive
        t.start()
    }

    /// 아무 스레드에서나. 앱이 늘 읽고 있어서 오래 막히지 않는다.
    func emit(_ ev: HelperEvent) {
        let frame = HelperProtocol.frame(ev.encode())
        outLock.lock(); defer { outLock.unlock() }
        var done = 0
        while done < frame.count {
            let n = frame.withUnsafeBytes { Darwin.write(outFD, $0.baseAddress! + done, $0.count - done) }
            if n > 0 { done += n; continue }
            if n < 0, errno == EINTR { continue }
            return  // 앱이 끝남. stdin EOF로 곧 정리한다
        }
    }

    // MARK: 명령 받기 (읽기 스레드)

    private func readLoop() {
        var decoder = HelperFrameDecoder()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buf.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { break }
            for body in decoder.append(Array(buf[0..<n])) {
                if let cmd = HelperCommand.decode(body) { handle(cmd) } else { HIDLog.warn("모르는 명령을 받았어요") }
            }
            if decoder.broken { HIDLog.error("앱이 보낸 메시지가 깨졌어요"); break }
        }
        finish()
    }

    /// 리포트는 읽기 스레드에서 바로 BluetoothHID에 넘긴다 (쓰기 큐로 가서 막히지 않음, 도우미 메인이 멈춰도 나간다).
    /// 연결·설정은 IOBluetooth 콜백과 같은 메인 스레드에서.
    private func handle(_ cmd: HelperCommand) {
        switch cmd {
        case .keyboard(let r): hid.send(r)
        case let .keyboardSequence(rs, gap): hid.send(rs, gap: TimeInterval(gap) / 1000)
        case .consumer(let u): hid.send(ConsumerReport(usage: u))
        case let .move(dx, dy): hid.move(dx: Int(dx), dy: Int(dy))
        case let .scroll(w, p): hid.scroll(wheel: Int(w), pan: Int(p))
        case .buttons(let b): hid.setButtons(b)
        case let .click(b, hold): hid.click(button: Int(b), hold: TimeInterval(hold) / 1000)
        case .emptyReports: hid.sendEmptyReports()
        case .ping(let s):
            // 메인이 답해야 "살아 있음"
            DispatchQueue.main.async { self.emit(.pong(s)) }
        case .flush(let s):
            // 앞의 리포트는 이미 쓰기 큐에 들어갔다. 읽기 스레드를 막지 않게 다른 곳에서 기다린다
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = self.hid.writeStatistics(timeout: 0.5) != nil
                self.emit(.flushed(s, ok: ok))
            }
        case .motionDiagnostics(let s):
            DispatchQueue.global(qos: .userInitiated).async {
                let d = self.hid.takeMotionDiagnostics().map {
                    MotionDiagnostics(sends: $0.sends, maxSplit: $0.maxSplit, maxWriteMs: $0.maxWriteMs)
                }
                self.emit(.motionDiagnostics(s, d))
            }
        case .shutdown:
            finish()
        default:
            DispatchQueue.main.async { self.handleOnMain(cmd) }
        }
    }

    private func handleOnMain(_ cmd: HelperCommand) {
        switch cmd {
        case .publish(let name):
            do { try hid.publishServiceRecord(name: name) } catch { emit(.failure("\(error)")) }
        case .unpublish: hid.removeServiceRecord()
        case .listen: hid.listen()
        case .stopListening: hid.stopListening()
        case .connect(let address):
            do { try hid.connect(address: address) } catch { emit(.failure("\(error)")) }
        case .disconnect: hid.disconnect()
        case .setDefaultAddress(let a): hid.defaultAddress = a
        case .setAutoReconnect(let on): hid.autoReconnect = on
        case .cancelReconnect: hid.cancelReconnect()
        case .resetReconnectPolicy: hid.resetReconnectPolicy()
        case let .setAcceptPolicy(address, all):
            acceptAddress = address
            acceptAll = all
        default: break
        }
    }

    private let finishLock = NSLock()
    private var finishing = false

    /// 끊고 정리한 뒤 끝낸다. 메인이 IOBluetooth에 붙잡혀 있어도 3초 뒤엔 끝낸다.
    private func finish() {
        finishLock.lock()
        let already = finishing
        finishing = true
        finishLock.unlock()
        guard !already else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { exit(0) }
        DispatchQueue.main.async {
            self.hid.autoReconnect = false
            self.hid.cancelReconnect()
            self.hid.disconnect()
            self.hid.stopListening()
            self.hid.removeServiceRecord()
            exit(0)
        }
    }

    // MARK: BluetoothHIDDelegate (메인)

    func hid(_ hid: BluetoothHID, didChange state: BluetoothHID.State) { emit(.state(state)) }

    func hid(_ hid: BluetoothHID, shouldAccept device: IOBluetoothDevice) -> Bool {
        let address = device.addressString ?? ""
        if acceptAll { return true }
        if let a = acceptAddress, a.lowercased() == address.lowercased() { return true }
        emit(.incomingRejected(address: address, name: device.name ?? ""))
        return false
    }

    func hid(_ hid: BluetoothHID, didReceive leds: KeyboardLEDs) { emit(.leds(leds.rawValue)) }
    func hidTransportStalled(_ hid: BluetoothHID) { emit(.stalled) }
    func hidNeedsFreshProcess(_ hid: BluetoothHID) { emit(.needsFreshProcess) }
    func hid(_ hid: BluetoothHID, didScheduleReconnect at: Date?) {
        emit(.reconnectScheduled(seconds: at.map { max(0, $0.timeIntervalSinceNow) }))
    }
}

// stdout은 메시지 전용으로 따로 떼어 두고, 1번은 stderr로 돌린다 (어디선가 print해도 메시지가 깨지지 않게)
signal(SIGPIPE, SIG_IGN)
let messageFD = dup(STDOUT_FILENO)
dup2(STDERR_FILENO, STDOUT_FILENO)
let server = HelperServer(outFD: messageFD)
server.start()
RunLoop.main.run()
