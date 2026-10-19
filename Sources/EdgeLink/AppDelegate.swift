import AppKit
import Combine
import CoreBluetooth
import EdgeLinkCore
import IOBluetooth
import ServiceManagement
import SwiftUI

@main
struct EdgeLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.model.settings)
                .environmentObject(delegate.model.permissions)
        } label: {
            MenuBarIcon(model: delegate.model, permissions: delegate.model.permissions, settings: delegate.model.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // EdgeLink가 두 개 실행되면 나중에 켠 것을 끈다
        let mine = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: mine)
            .filter { $0 != NSRunningApplication.current }
        if !mine.isEmpty, let first = others.first, Snapshot.directory == nil {
            first.activate()
            NSApp.terminate(nil)
            return
        }
        model.launch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

// MARK: - 앱 상태

/// 연결 상태 4개 (설계 문서 › 상태와 예외 처리)
enum ConnectionPhase: Equatable {
    case idle
    case pairing(code: Int?)
    case connecting
    case connected(name: String)
    case failed(message: String)
}

final class AppModel: NSObject, ObservableObject {
    let settings = AppSettings()
    let permissions = Permissions()
    let devices = DeviceDirectory()
    let hid = BluetoothHID()

    @Published private(set) var connection: ConnectionPhase = .idle
    @Published private(set) var connectingAddress: String?
    @Published var onboardingPage: OnboardingStep = .welcome {
        didSet { if onboardingPage != oldValue { enforceOnboardingGates() } }
    }
    /// Mac 블루투스 전원
    @Published private(set) var bluetoothPoweredOn = BluetoothHID.hostInfo()?.poweredOn ?? true
    /// 모니터 목록과 놓을 수 있는 자리. 모니터 구성이 바뀔 때만 다시 계산한다.
    @Published private(set) var screens: [ScreenInfo] = Layout.screens()
    @Published private(set) var placements: [Placement] = []
    /// 페어링 화면이 보이는 동안만 새 기기의 연결을 받는다
    var acceptingNewDevice = false

    /// Mac 조작 / 아이폰 조작 / 보정 중. InputRouter가 바꾼다.
    @Published var controlMode: ControlMode = .mac
    lazy var router = InputRouter(model: self)
    lazy var toasts = ToastCenter()
    lazy var dialogs = DialogPresenter(model: self)
    lazy var settingsWindow = SettingsWindowController(model: self)

    private var bluetoothStarted = false
    private var pairer: Pairer?
    private var circleTimer: Timer?
    private var onboardingWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var powerWatch: CBCentralManager?

    override init() {
        super.init()
        hid.delegate = self
        // 하위 객체가 바뀌면 메뉴바 아이콘도 다시 그린다
        placements = Layout.placements(screens)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reloadScreens() }.store(in: &bag)
        permissions.$bluetooth.removeDuplicates().sink { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                if state == .granted {
                    self.watchBluetoothPower()
                    self.startBluetoothIfAllowed()
                } else {
                    // 권한이 꺼지면 정리하고, 다시 켜지면 SDP 등록부터 다시 한다
                    self.stopBluetooth()
                }
            }
        }.store(in: &bag)
        // 온보딩 중 필수 권한이 꺼지면 권한 단계로 돌아간다
        permissions.$revoked.sink { [weak self] kind in
            guard kind != nil else { return }
            DispatchQueue.main.async { self?.enforceOnboardingGates() }
        }.store(in: &bag)
    }

    var isConnected: Bool { if case .connected = connection { return true } else { return false } }

    /// 개발용 화면 캡처에서만: 연결 상태를 흉내 낸다
    func debugSetConnection(_ phase: ConnectionPhase) {
        guard Snapshot.directory != nil else { return }
        connection = phase
    }

    // MARK: 화면 사이 연결 (Contracts.swift)

    func openSettings(_ tab: SettingsTab = .general) { settingsWindow.show(tab: tab) }
    func showToast(_ text: String, systemImage: String? = nil) { toasts.show(text, systemImage: systemImage) }
    func present(_ dialog: AppDialog) { dialogs.present(dialog) }

    /// 클립보드 보내기 (팝오버 버튼, ⌃⌥⌘V). 첫 사용이거나 영문 외 글자가 섞이면 확인 창부터.
    func requestClipboardSend() {
        guard settings.clipboardTypingAllowed else { return showToast("회사 정책으로 클립보드 보내기가 꺼져 있어요") }
        guard isConnected else { return showToast("아이폰을 연결하면 쓸 수 있어요") }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else { return showToast("클립보드가 비어 있어요") }
        let sendable = text.filter { HIDUsage.fromASCII($0) != nil }.count
        let skipped = text.count - sendable
        if !settings.clipboardConfirmSkip || skipped > 0 {
            present(.clipboardConfirm(sendable: sendable, skipped: skipped))
        } else {
            router.typeClipboard()
        }
    }

    /// 확인 창에서 "보내기"를 눌렀을 때
    func confirmClipboardSend(dontAskAgain: Bool) {
        if dontAskAgain { settings.clipboardConfirmSkip = true }
        router.typeClipboard()
    }

    /// 연결 요청 확인 창에서 허용: 그 기기를 새 기본 기기로 정하고 연결한다
    func acceptConnectionRequest(address: String, name: String) {
        settings.lastDeviceAddress = address
        settings.lastDeviceName = name
        hid.defaultAddress = address
        connect(address: address)
    }

    /// 설정 › 연결 › 페어링 초기화 확인 창에서 "초기화"
    func resetPairing() {
        router.returnToMac(.menu)
        disconnect()
        if let address = settings.lastDeviceAddress, let d = IOBluetoothDevice(addressString: address),
           d.responds(to: Selector(("remove"))) {
            // 비공개 API라 있을 때만 (Mac 쪽 페어링 삭제)
            d.perform(Selector(("remove")))
        }
        settings.resetPairing()
        openOnboarding(at: .welcome)
    }
    var connectedName: String? { if case let .connected(name) = connection { return name } else { return nil } }

    // MARK: 시작 · 종료

    func launch() {
        if Snapshot.directory != nil { return Snapshot.run(model: self) }
        // 개발용: 온보딩을 마쳤어도 창을 바로 연다
        if let v = ProcessInfo.processInfo.environment["EDGELINK_SHOW_ONBOARDING"] {
            openOnboarding(at: Int(v).flatMap(OnboardingStep.init(rawValue:)) ?? .layout)
        }
        if settings.onboardingDone {
            startBluetoothIfAllowed()
        } else {
            openOnboarding()
        }
        startRouterIfAllowed()
        permissions.$accessibility.combineLatest(permissions.$inputMonitoring)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.startRouterIfAllowed() } }
            .store(in: &bag)
    }

    /// 이벤트 탭은 손쉬운 사용·입력 모니터링이 있을 때만. 꺼지면 InputRouter가 Mac으로 돌아온다.
    func startRouterIfAllowed() {
        if permissions.accessibility && permissions.inputMonitoring {
            router.start()
        } else {
            router.returnToMac(.permissionLost)
            router.stop()
        }
    }

    func shutdown() {
        router.returnToMac(.menu)
        router.stop()
        stopCircle()
        hid.disconnect()
        hid.stopListening()
        hid.removeServiceRecord()
    }

    /// 블루투스는 온보딩 2단계(권한) 전에는 쓰지 않는다. 설명 없이 시스템 창이 먼저 뜨지 않게.
    func startBluetoothIfAllowed() {
        guard !bluetoothStarted, permissions.bluetooth == .granted else { return }
        guard settings.onboardingDone || settings.onboardingStep >= OnboardingStep.permissions.rawValue else { return }
        do {
            try hid.publishServiceRecord()
        } catch {
            HIDLog.error("\(error)")
            connection = .failed(message: "\(error)")
            return
        }
        bluetoothStarted = true
        hid.autoReconnect = settings.autoReconnect
        hid.defaultAddress = settings.lastDeviceAddress
        hid.listen()
        if settings.onboardingDone, let address = settings.lastDeviceAddress {
            connect(address: address)
        }
    }

    func reloadScreens() {
        screens = Layout.screens()
        placements = Layout.placements(screens)
    }

    /// 저장한 아이폰 자리 (모니터가 없으면 nil)
    var currentPlacement: Placement? { Layout.find(settings.phoneLayout, in: placements) }

    /// 권한이 있을 때만 만든다 (만들어도 권한 창이 뜨지 않음). 전원이 켜지면 다시 시작한다.
    private func watchBluetoothPower() {
        guard powerWatch == nil, permissions.bluetooth == .granted else { return }
        powerWatch = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func stopBluetooth() {
        guard bluetoothStarted else { return }
        hid.disconnect()
        hid.stopListening()
        hid.removeServiceRecord()
        bluetoothStarted = false
    }

    // MARK: 연결

    /// 페어링이 안 된 기기면 페어링부터 하고 HID로 연결한다.
    func connect(address: String) {
        startBluetoothIfAllowed()
        guard bluetoothStarted else { return }
        connectingAddress = address
        let paired = IOBluetoothDevice(addressString: address)?.isPaired() ?? false
        if paired {
            connection = .connecting
            do { try hid.connect(address: address) } catch {
                connection = .failed(message: "\(error)")
            }
            return
        }
        let p = Pairer()
        p.onCode = { [weak self] code in self?.connection = .pairing(code: code) }
        p.onFinish = { [weak self] result in
            guard let self else { return }
            self.pairer = nil
            self.devices.reloadPaired()
            if result == kIOReturnSuccess {
                // 아이폰이 먼저 연결해 왔으면 그대로 둔다
                switch self.hid.state {
                case .connected, .connecting: return
                default: break
                }
                self.connection = .connecting
                do { try self.hid.connect(address: address) } catch {
                    self.connection = .failed(message: "\(error)")
                }
            } else {
                self.connection = .failed(message: "페어링하지 못했어요 (\(BluetoothHID.describe(result)))")
            }
        }
        pairer = p
        connection = .pairing(code: nil)
        let r = p.start(address: address)
        if r != kIOReturnSuccess {
            pairer = nil
            connection = .failed(message: "페어링을 시작하지 못했어요 (\(BluetoothHID.describe(r)))")
        }
    }

    func disconnect() {
        pairer?.cancel()
        pairer = nil
        hid.disconnect()
        connection = .idle
    }

    // MARK: 연결 확인 (온보딩 5단계)

    /// 아이폰 커서를 화면 가운데로 옮긴 뒤 원 모양으로 계속 움직인다.
    /// Mac은 아이폰 커서 위치를 모르므로, 왼쪽 위 구석으로 크게 밀어 (0, 0)에 맞춘 다음 가운데로 간다.
    func startCircle() {
        stopCircle()
        let radius = 120.0, speed = 2 * Double.pi / 2.0 // 2초에 한 바퀴
        let dt = 1.0 / 60
        let size = settings.profile.model.screenSize
        let (w, h) = settings.profile.landscape ? (size.height, size.width) : (size.width, size.height)
        let k = settings.unitsPerPoint > 0 ? settings.unitsPerPoint : 2.0
        // 원의 시작점(각도 0)은 가운데에서 오른쪽으로 반지름만큼
        var toGo = (x: w / 2 * k + radius, y: h / 2 * k)
        var cornerTicks = 18          // 0.3초 동안 왼쪽 위로 크게 민다 (5000 단위 넘게)
        let step = 6.0                // 가운데로 갈 땐 천천히 (포인터 가속을 피함)
        var angle = 0.0
        var carry = (x: 0.0, y: 0.0)
        circleTimer = Timer(timeInterval: dt, repeats: true) { [weak self] _ in
            guard let self, self.isConnected else { return }
            if cornerTicks > 0 {
                cornerTicks -= 1
                self.hid.move(dx: -300, dy: -300)
                return
            }
            if toGo.x > 0 || toGo.y > 0 {
                let dx = min(step, toGo.x), dy = min(step, toGo.y)
                toGo.x -= dx; toGo.y -= dy
                self.hid.move(dx: Int(dx), dy: Int(dy))
                return
            }
            let next = angle + speed * dt
            carry.x += radius * (cos(next) - cos(angle))
            carry.y += radius * (sin(next) - sin(angle))
            angle = next
            let dx = Int(carry.x.rounded(.towardZero)), dy = Int(carry.y.rounded(.towardZero))
            carry.x -= Double(dx); carry.y -= Double(dy)
            if dx != 0 || dy != 0 { self.hid.move(dx: dx, dy: dy) }
        }
        RunLoop.main.add(circleTimer!, forMode: .common)
    }

    func stopCircle() {
        circleTimer?.invalidate()
        circleTimer = nil
    }

    /// 영문·숫자·기호를 12ms 간격으로 타이핑한다.
    func type(_ text: String) {
        let reports = text.compactMap(HIDUsage.typingReports(for:)).flatMap { $0 }
        var i = 0
        let t = Timer(timeInterval: 0.012, repeats: true) { [weak self] t in
            guard let self, i < reports.count, self.isConnected else { t.invalidate(); return }
            self.hid.send(reports[i])
            i += 1
        }
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: 로그인 항목

    var loginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            HIDLog.warn("로그인 항목 변경 실패: \(error.localizedDescription)")
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
        objectWillChange.send()
    }

    // MARK: 창

    func openOnboarding(at step: OnboardingStep? = nil) {
        onboardingPage = step ?? resumeStep()
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView()
                .environmentObject(self)
                .environmentObject(settings)
                .environmentObject(permissions)
                .environmentObject(devices))
            // 창 크기를 SwiftUI가 다시 맞추지 않게 한다 (제목 표시줄 높이만큼 아래에 빈 띠가 생겼음)
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "EdgeLink 시작하기"
            // 제목 표시줄이 내용 위에 겹치는 창이라, 내용 크기가 아니라 창 전체 크기를 720×560으로 둔다
            let size = NSSize(width: 720, height: 560)
            w.setFrame(NSRect(origin: .zero, size: size), display: false)
            w.minSize = size
            w.maxSize = size
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    /// 멈춘 단계부터 이어서. 앞 단계 조건이 풀렸으면 그 단계로 돌아간다.
    func resumeStep() -> OnboardingStep {
        let next = OnboardingStep(rawValue: min(settings.onboardingStep + 1, OnboardingStep.done.rawValue)) ?? .welcome
        return gate(next)
    }

    /// 단계를 끝냈다고 저장하고 다음으로. 앞 단계 조건이 풀려 있으면 그 단계로.
    func complete(_ step: OnboardingStep) {
        settings.onboardingStep = max(settings.onboardingStep, step.rawValue)
        if step == .permissions { startBluetoothIfAllowed() }
        if let next = OnboardingStep(rawValue: step.rawValue + 1) { onboardingPage = gate(next) }
    }

    /// 필수 단계(권한, 페어링)를 건너뛰지 못하게 한다.
    func gate(_ step: OnboardingStep) -> OnboardingStep {
        if step.rawValue > OnboardingStep.permissions.rawValue, !permissions.allGranted { return .permissions }
        if step.rawValue > OnboardingStep.pairing.rawValue, settings.lastDeviceAddress == nil { return .pairing }
        return step
    }

    private func enforceOnboardingGates() {
        guard onboardingWindow != nil else { return }
        let allowed = gate(onboardingPage)
        if allowed != onboardingPage { onboardingPage = allowed }
    }

    func finishOnboarding() {
        settings.onboardingStep = OnboardingStep.done.rawValue
        settings.onboardingDone = true
        closeOnboarding()
    }
}

extension AppModel: BluetoothHIDDelegate {
    func hid(_ hid: BluetoothHID, didChange state: BluetoothHID.State) {
        switch state {
        case .idle:
            break
        case .connecting:
            if case .pairing = connection { return }
            connection = .connecting
        case let .connected(address):
            let device = IOBluetoothDevice(addressString: address)
            let name = device?.name ?? address
            settings.lastDeviceAddress = address
            settings.lastDeviceName = name
            if !settings.profile.manual, let m = DeviceProfile.Model.infer(from: name), m != settings.profile.model {
                settings.profile.model = m
            }
            hid.defaultAddress = address
            connectingAddress = nil
            connection = .connected(name: name)
        case let .disconnected(reason):
            stopCircleIfNeeded()
            router.returnToMac(.disconnected)
            switch reason {
            case .user: connection = .idle
            case let .openFailed(stage, code):
                connection = .failed(message: "\(stage) 실패 (\(BluetoothHID.describe(code)))")
            case .rejected:
                if case .pairing = connection { return }
                connection = .failed(message: "허용하지 않은 기기라 연결을 막았어요")
            case .virtualCableUnplug: connection = .failed(message: "아이폰에서 연결을 해제했어요")
            case .channelClosed, .stalled: connection = .failed(message: "연결이 끊겼어요")
            }
        }
    }

    /// 기본 기기만 연결 허용. 확인 창(캔버스 4-1)은 4단계에서 붙인다. 지금은 페어링 단계에서만 새 기기를 받는다.
    func hid(_ hid: BluetoothHID, shouldAccept device: IOBluetoothDevice) -> Bool {
        if device.addressString?.lowercased() == settings.lastDeviceAddress?.lowercased() { return true }
        if acceptingNewDevice || !settings.onlyDefaultDevice { return true }
        // 채널은 닫고 확인 창을 띄운다. 허용하면 그 기기로 Mac이 먼저 연결한다.
        let name = device.name ?? device.addressString ?? "이름 없는 기기"
        let address = device.addressString ?? ""
        DispatchQueue.main.async { self.present(.connectionRequest(name: name, address: address)) }
        return false
    }

    /// 블루투스 쓰기가 3번 연속 50ms를 넘으면 Mac으로 돌아온다
    func hidTransportStalled(_ hid: BluetoothHID) {
        router.returnToMac(.transportStalled)
    }

    func hid(_ hid: BluetoothHID, didReceive leds: KeyboardLEDs) {}

    private func stopCircleIfNeeded() {
        if onboardingPage != .test { stopCircle() }
    }
}

extension AppModel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === onboardingWindow else { return }
        stopCircle()
        devices.stop()
        acceptingNewDevice = false
        // 다음에 열 때 새로 만들어서 각 화면의 onAppear가 다시 불리게 한다
        DispatchQueue.main.async { self.onboardingWindow = nil }
    }
}

extension AppModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let on = central.state == .poweredOn
        guard on != bluetoothPoweredOn || (on && !bluetoothStarted) else { return }
        bluetoothPoweredOn = on
        if on {
            startBluetoothIfAllowed()
            if settings.onboardingDone, !isConnected, let a = settings.lastDeviceAddress { connect(address: a) }
        } else {
            hid.cancelReconnect()
            connection = .failed(message: "Mac 블루투스가 꺼져 있어요")
        }
    }
}

// MARK: - 메뉴바 아이콘

struct MenuBarIcon: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: Permissions
    @ObservedObject var settings: AppSettings

    var body: some View {
        Image(nsImage: Self.image(symbol: symbol, warning: warning))
            .accessibilityLabel(label)
    }

    private var warning: Bool {
        let p = model.permissions
        if p.revoked != nil { return true }
        guard model.settings.onboardingDone else { return false }
        if p.firstMissing != nil || !model.bluetoothPoweredOn { return true }
        if case .failed = model.connection { return true }
        return false
    }

    private var symbol: String {
        model.isConnected ? "iphone" : "iphone.slash"
    }

    private var label: String {
        if warning { return "EdgeLink · 문제 있음" }
        return model.isConnected ? "EdgeLink · 연결됨" : "EdgeLink · 연결 안 됨"
    }

    private static var cache: [String: NSImage] = [:]

    /// 18pt 템플릿 아이콘. 경고일 땐 주황 점을 덧그린다. 만든 이미지는 다시 쓴다.
    static func image(symbol: String, warning: Bool) -> NSImage {
        let key = "\(symbol)-\(warning)"
        if let img = cache[key] { return img }
        let img = makeImage(symbol: symbol, warning: warning)
        cache[key] = img
        return img
    }

    private static func makeImage(symbol: String, warning: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        guard warning else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let tinted = base.copy() as! NSImage
            tinted.lockFocus()
            NSColor.labelColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let s = tinted.size
            tinted.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            NSColor(hex: 0xFF9500).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width - 7, y: rect.height - 7, width: 6, height: 6)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
