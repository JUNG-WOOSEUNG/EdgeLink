// bthid — 1단계 연결 검증 도구.
// Mac이 블루투스 HID 키보드·마우스로 아이폰에 붙는지, 지연이 얼마인지 확인한다.

import ApplicationServices
import EdgeLinkCore
import Foundation
import IOBluetooth

let usage = """
사용법: bthid <명령> [옵션]

  info                    Mac 블루투스 상태 (이름, 주소, 기기 종류)
  list                    페어링한 기기 목록
  scan [초]               근처 기기 찾기 (기본 10초)
  pair <주소>             기기와 페어링 (아이폰은 블루투스 설정 화면을 열어두세요)
  sdp                     HID 디스크립터와 SDP 레코드 출력 (블루투스 안 씀)
  connect <주소>          Mac에서 아이폰으로 HID 연결 후 시험 동작
  serve                   SDP를 등록하고 아이폰에서 연결해 오기를 기다림
  tap [초]                이벤트 탭 권한 시험 (손쉬운 사용만으로 가로채기 되는지)

connect · serve 옵션:
  --cod                   잠시 Mac을 키보드 종류(0x0025C0)로 보이게 함
  --text <글자>           시험으로 입력할 글자 (기본 "hello edgelink")
  --no-demo               사각형 이동·글자 입력 생략
  --interactive           연결 후 터미널 입력을 아이폰으로 보냄 (방향키 = 커서)
  --exit                  시험 동작 후 끊고 종료 (기본은 Ctrl-C까지 유지)
  -v                      자세한 로그
"""

// MARK: - 인자

struct Options {
    var command = ""
    var positional: [String] = []
    var cod = false
    var text = "hello edgelink"
    var demo = true
    var interactive = false
    var exitAfterDemo = false
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else { return o }
    o.command = args.removeFirst()
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--cod": o.cod = true
        case "--text": o.text = args.isEmpty ? o.text : args.removeFirst()
        case "--no-demo": o.demo = false
        case "--interactive", "-i": o.interactive = true
        case "--exit": o.exitAfterDemo = true
        case "-v", "--verbose": HIDLog.verbose = true
        default: o.positional.append(a)
        }
    }
    return o
}

func out(_ s: String) { print(s); fflush(stdout) }

func die(_ message: String) -> Never {
    FileHandle.standardError.write("오류: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func describeClass(_ cod: BluetoothClassOfDevice) -> String {
    let major = (cod >> 8) & 0x1F
    let minor = (cod >> 2) & 0x3F
    let majors: [UInt32: String] = [1: "컴퓨터", 2: "전화", 4: "오디오", 5: "주변기기", 7: "웨어러블"]
    return String(format: "0x%06X (%@, minor 0x%02X)", cod, majors[major] ?? "기타 \(major)", minor)
}

// MARK: - info · list · sdp

func cmdInfo() {
    guard let h = BluetoothHID.hostInfo() else { die("블루투스 컨트롤러를 찾지 못했어요") }
    out("이름      \(h.name)")
    out("주소      \(h.address)")
    out("기기 종류 \(describeClass(h.classOfDevice))")
    out("전원      \(h.poweredOn ? "켜짐" : "꺼짐")")
}

func cmdList() {
    let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    guard !devices.isEmpty else {
        out("페어링한 기기가 없어요. `bthid scan` 후 `bthid pair <주소>`로 페어링하세요.")
        return
    }
    for d in devices {
        let connected = d.isConnected() ? "연결됨" : "-"
        out("\(d.addressString ?? "?")  \(connected.padding(toLength: 4, withPad: " ", startingAt: 0))  \(describeClass(d.classOfDevice))  \(d.name ?? "")")
    }
}

func cmdSDP() {
    out("HID 디스크립터 (\(HIDDescriptor.bytes.count)바이트)")
    out(hex(HIDDescriptor.bytes))
    out("")
    out("SDP 레코드")
    let dict = HIDServiceRecord.dictionary()
    for key in dict.keys.sorted() { out("  \(key)") }
    out("")
    out("예시 리포트")
    out("  키보드 'a'   \(hex(KeyboardReport(keys: [0x04]).bytes))")
    out("  마우스 +10,-5 \(hex(MouseReport(dx: 10, dy: -5).bytes))")
    out("  볼륨 업      \(hex(ConsumerReport(usage: ConsumerReport.volumeUp).bytes))")
}

// MARK: - scan · pair

final class Scanner: NSObject, IOBluetoothDeviceInquiryDelegate {
    var inquiry: IOBluetoothDeviceInquiry!

    func start(seconds: Int) {
        inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry.inquiryLength = UInt8(clamping: seconds)
        inquiry.updateNewDeviceNames = true
        let r = inquiry.start()
        guard r == kIOReturnSuccess else { die("찾기 시작 실패: \(BluetoothHID.describe(r))") }
        out("\(seconds)초 동안 찾아요. 아이폰은 설정 › 블루투스 화면을 열어두세요.")
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let d = device else { return }
        out("\(d.addressString ?? "?")  \(describeClass(d.classOfDevice))  \(d.name ?? "(이름 없음)")")
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        guard let d = device else { return }
        out("  이름 확인 \(d.addressString ?? "?") → \(d.name ?? "")")
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        out("찾기 끝 (\(BluetoothHID.describe(error)))")
        exit(0)
    }
}

final class Pairer: NSObject, IOBluetoothDevicePairDelegate {
    var pair: IOBluetoothDevicePair!

    func start(address: String) {
        guard let d = IOBluetoothDevice(addressString: address) else { die("주소 형식이 아니에요: \(address)") }
        pair = IOBluetoothDevicePair(device: d)
        pair.delegate = self
        let r = pair.start()
        guard r == kIOReturnSuccess else { die("페어링 시작 실패: \(BluetoothHID.describe(r))") }
        out("\(d.nameOrAddress)와 페어링을 시작해요")
    }

    func devicePairingConnecting(_ sender: Any!) { out("연결 중…") }
    func devicePairingConnected(_ sender: Any!) { out("연결됨, 인증 중…") }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        out(String(format: "확인 번호 %06u — 아이폰에 같은 번호가 보이면 아이폰에서 '페어링'을 누르세요", numericValue))
        pair.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        out(String(format: "아이폰에 %06u을 입력하세요", passkey))
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        out("PIN 요청: 0000으로 응답해요")
        var pin = BluetoothPINCode()
        withUnsafeMutableBytes(of: &pin) { raw in for (i, c) in "0000".utf8.enumerated() { raw[i] = c } }
        pair.replyPINCode(4, pinCode: &pin)
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        if error == kIOReturnSuccess {
            out("페어링 완료. 이제 `bthid connect \(pair.device()?.addressString ?? "<주소>")`")
            exit(0)
        }
        die("페어링 실패: \(BluetoothHID.describe(error))")
    }
}

// MARK: - connect · serve

final class Session: NSObject, BluetoothHIDDelegate {
    let hid = BluetoothHID()
    let options: Options
    private var demoStarted = false
    private var shuttingDown = false
    private var terminal: RawTerminal?

    init(options: Options) {
        self.options = options
        super.init()
        hid.delegate = self
    }

    func prepare() {
        if options.cod {
            let r = BluetoothHID.setClassOfDevice(for: 600)
            out("기기 종류를 키보드로 바꿔요: \(BluetoothHID.describe(r))")
        }
        do { try hid.publishServiceRecord() } catch { die("\(error)") }
    }

    func connect(address: String) {
        prepare()
        do { try hid.connect(address: address) } catch { die("\(error)") }
    }

    func serve() {
        prepare()
        hid.listen()
        out("아이폰 설정 › 블루투스에서 이 Mac을 눌러 연결하세요. (Mac은 시스템 설정 › 블루투스 화면을 열어두면 검색돼요)")
    }

    func shutdown() {
        shuttingDown = true
        terminal?.restore()
        hid.disconnect()
        hid.stopListening()
        hid.removeServiceRecord()
        let stats = hid.writeStatistics()
        if stats.count > 0 { out(stats.summary) }
    }

    // BluetoothHIDDelegate

    func hid(_ hid: BluetoothHID, didChange state: BluetoothHID.State) {
        switch state {
        case .connected:
            guard !demoStarted else { return }
            demoStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.runAfterConnect() }
        case .disconnected(let reason):
            guard !shuttingDown else { return }
            out("연결 끊김: \(reason)")
            if case .openFailed = reason {
                out("""
                힌트:
                  - 아이폰이 이 Mac과 페어링돼 있는지 확인 (`bthid list`)
                  - `bthid serve`로 아이폰 쪽에서 연결해보기
                  - `--cod`로 기기 종류를 키보드로 바꿔보기
                """)
            }
            if demoStarted || reason != .channelClosed { terminal?.restore(); hid.removeServiceRecord(); exit(1) }
        default:
            break
        }
    }

    func hid(_ hid: BluetoothHID, shouldAccept device: IOBluetoothDevice) -> Bool {
        out("연결 요청: \(device.nameOrAddress) → 허용 (시험 도구)")
        return true
    }

    func hid(_ hid: BluetoothHID, didReceive leds: KeyboardLEDs) {
        out("아이폰 LED: Caps Lock \(leds.contains(.capsLock) ? "켜짐" : "꺼짐")")
    }

    func hidTransportStalled(_ hid: BluetoothHID) {
        out("경고: 쓰기 지연이 3번 연속 50ms를 넘었어요")
    }

    // 시험 동작

    private func runAfterConnect() {
        guard options.demo else { return afterDemo() }
        out("시험 1/2: 아이폰 커서를 사각형으로 움직여요")
        hid.resetWriteStatistics()
        let side = 400, step = 10, perSide = side / step
        let moves: [(Int, Int)] = [(step, 0), (0, step), (-step, 0), (0, -step)]
        var steps: [(Int, Int)] = []
        for m in moves { steps += Array(repeating: m, count: perSide) }
        runSteps(steps, interval: 0.016) {
            out("시험 2/2: 아이폰 메모 앱을 열고 입력 칸을 눌러두세요. 3초 뒤 \"\(self.options.text)\"를 입력해요")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.type(self.options.text) {
                    out(self.hid.writeStatistics().summary)
                    self.afterDemo()
                }
            }
        }
    }

    private func afterDemo() {
        if options.interactive {
            startInteractive()
        } else if options.exitAfterDemo {
            shutdown()
            exit(0)
        } else {
            out("연결을 유지해요. Ctrl-C로 끝내요. (--interactive로 터미널 입력을 보낼 수 있어요)")
        }
    }

    private func runSteps(_ steps: [(Int, Int)], interval: TimeInterval, done: @escaping () -> Void) {
        var i = 0
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            guard i < steps.count else { t.invalidate(); done(); return }
            self.hid.move(dx: steps[i].0, dy: steps[i].1)
            i += 1
        }
    }

    /// 글자마다 누름·뗌, 12ms 간격 (설계 문서: 클립보드 보내기 간격).
    private func type(_ text: String, done: @escaping () -> Void) {
        let chars = Array(text)
        var skipped = 0
        var reports: [KeyboardReport] = []
        for c in chars {
            if let r = HIDUsage.typingReports(for: c) { reports += r } else { skipped += 1 }
        }
        if skipped > 0 { out("영문·숫자·기호가 아닌 \(skipped)글자는 뺐어요") }
        var i = 0
        Timer.scheduledTimer(withTimeInterval: 0.012, repeats: true) { t in
            guard i < reports.count else { t.invalidate(); done(); return }
            self.hid.send(reports[i])
            i += 1
        }
    }

    private func startInteractive() {
        out("터미널 입력을 아이폰으로 보내요. 방향키 = 커서, Ctrl-] = 클릭, Ctrl-C = 끝내기")
        terminal = RawTerminal()
        let input = FileHandle.standardInput
        input.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self, !data.isEmpty else { return }
            DispatchQueue.main.async { self.handleInput(Array(data)) }
        }
    }

    private func handleInput(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x03 { shutdown(); exit(0) }                     // Ctrl-C
            if b == 0x1D { hid.click(button: 1); i += 1; continue }  // Ctrl-]
            if b == 0x1B, i + 2 < bytes.count, bytes[i + 1] == 0x5B {  // ESC [ A/B/C/D
                switch bytes[i + 2] {
                case 0x41: hid.move(dx: 0, dy: -40)
                case 0x42: hid.move(dx: 0, dy: 40)
                case 0x43: hid.move(dx: 40, dy: 0)
                case 0x44: hid.move(dx: -40, dy: 0)
                default: break
                }
                i += 3
                continue
            }
            if b == 0x7F {                                           // Backspace
                hid.send(KeyboardReport(keys: [0x2A])); hid.send(KeyboardReport())
            } else if let reports = HIDUsage.typingReports(for: Character(Unicode.Scalar(b))) {
                reports.forEach(hid.send)
            }
            i += 1
        }
    }
}

/// 입력 모드에서 터미널을 한 글자씩 읽게 한다.
final class RawTerminal {
    private var original = termios()
    private var active = false

    init() {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        active = true
    }

    func restore() {
        guard active else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        active = false
    }
}

// MARK: - tap

/// 손쉬운 사용 권한만으로 키 입력을 가로챌 수 있는지 확인한다. 키 내용은 보지 않고 개수만 센다.
final class TapProbe {
    var counts: [String: Int] = [:]
    var taps: [CFMachPort] = []

    func run(seconds: Int) {
        out("손쉬운 사용        \(AXIsProcessTrusted() ? "허용" : "없음")")
        out("입력 모니터링      \(CGPreflightListenEventAccess() ? "허용" : "없음")")
        out("(터미널에서 실행하면 권한은 터미널 앱 기준이에요)")
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        for (name, option) in [("가로채기(defaultTap)", CGEventTapOptions.defaultTap),
                               ("엿듣기(listenOnly)", CGEventTapOptions.listenOnly)] {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: option,
                                              eventsOfInterest: mask, callback: option == .defaultTap ? tapCallbackDefault : tapCallbackListen,
                                              userInfo: refcon) else {
                out("\(name.padding(toLength: 18, withPad: " ", startingAt: 0)) 탭 생성 실패")
                continue
            }
            let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            taps.append(tap)
            counts[name] = 0
            out("\(name.padding(toLength: 18, withPad: " ", startingAt: 0)) 탭 생성 성공")
        }
        guard !taps.isEmpty else { exit(1) }
        out("\(seconds)초 동안 아무 키나 눌러보세요 (내용은 기록하지 않아요)")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            for (k, v) in self.counts.sorted(by: { $0.key < $1.key }) { out("\(k): 키 이벤트 \(v)개 받음") }
            exit(0)
        }
    }
}

private func tapCallbackDefault(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon, type == .keyDown { Unmanaged<TapProbe>.fromOpaque(refcon).takeUnretainedValue().counts["가로채기(defaultTap)", default: 0] += 1 }
    return Unmanaged.passUnretained(event)
}

private func tapCallbackListen(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon, type == .keyDown { Unmanaged<TapProbe>.fromOpaque(refcon).takeUnretainedValue().counts["엿듣기(listenOnly)", default: 0] += 1 }
    return Unmanaged.passUnretained(event)
}

// MARK: - 실행

let options = parseOptions()
var keepAlive: [AnyObject] = []

func installSignalHandlers(_ session: Session) {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    for sig in [SIGINT, SIGTERM] {
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            out("\n끝내는 중…")
            session.shutdown()
            exit(0)
        }
        src.resume()
        keepAlive.append(src)
    }
}

switch options.command {
case "info":
    cmdInfo()
case "list":
    cmdList()
case "sdp":
    cmdSDP()
case "scan":
    let s = Scanner()
    keepAlive.append(s)
    s.start(seconds: Int(options.positional.first ?? "") ?? 10)
    RunLoop.main.run()
case "pair":
    guard let addr = options.positional.first else { die("주소가 필요해요: bthid pair <주소>") }
    let p = Pairer()
    keepAlive.append(p)
    p.start(address: addr)
    RunLoop.main.run()
case "connect":
    guard let addr = options.positional.first else { die("주소가 필요해요: bthid connect <주소>") }
    let session = Session(options: options)
    keepAlive.append(session)
    installSignalHandlers(session)
    session.connect(address: addr)
    RunLoop.main.run()
case "serve":
    let session = Session(options: options)
    keepAlive.append(session)
    installSignalHandlers(session)
    session.serve()
    RunLoop.main.run()
case "tap":
    let probe = TapProbe()
    keepAlive.append(probe)
    probe.run(seconds: Int(options.positional.first ?? "") ?? 10)
    RunLoop.main.run()
default:
    out(usage)
    exit(options.command.isEmpty || options.command == "help" || options.command == "-h" ? 0 : 1)
}
