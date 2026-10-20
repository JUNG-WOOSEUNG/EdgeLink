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
    /// 캡처 모드에선 메뉴 막대에 두 번째 아이콘이 잠깐 생기지 않게 넣지 않는다
    @State private var showInMenuBar = Snapshot.directory == nil

    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
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
            // 나중에 켠 쪽은 정리 절차 없이 끈다 (먼저 켠 앱의 충돌 복구 표시를 건드리지 않게)
            isDuplicate = true
            first.activate()
            NSApp.terminate(nil)
            return
        }
        model.launch()
    }

    private var isDuplicate = false

    func applicationWillTerminate(_ notification: Notification) {
        guard !isDuplicate else { return }
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
    let settings = AppSettings(defaults: Snapshot.directory != nil ? Snapshot.defaults : .standard)
    let permissions = Permissions()
    let devices = DeviceDirectory()
    /// 블루투스 HID는 도우미 프로세스(edgelink-hid)가 맡는다. 화면 캡처 모드에선 띄우지 않는다 (블루투스를 시작하지 않음).
    let hid = HIDHelperClient(launcher: HIDHelperClient.processLauncher(executable: HIDHelperClient.bundledHelperURL))

    @Published private(set) var connection: ConnectionPhase = .idle {
        didSet { trackConnection(from: oldValue) }
    }
    /// 연결·페어링을 시작한 시각 (팝오버에서 몇 초가 지나면 "취소"를 보인다)
    @Published private(set) var connectingSince: Date?
    /// 연결되기 전까지 이어진 실패 횟수 (같은 실패가 이어질 때만 회사 정책 안내)
    @Published private(set) var failureStreak = 0
    /// 사용자가 기기 메뉴에서 직접 끊음 (자동으로 다시 연결하지 않는다)
    @Published private(set) var disconnectedByUser = false
    @Published private(set) var connectingAddress: String?
    /// 마지막으로 끊긴 시각 (팝오버 "3분 전에 끊겼어요")
    @Published private(set) var disconnectedAt: Date?
    @Published var onboardingPage: OnboardingStep = .welcome {
        didSet { if onboardingPage != oldValue { enforceOnboardingGates() } }
    }
    /// Mac 블루투스 전원
    @Published private(set) var bluetoothPoweredOn = BluetoothHID.hostInfo()?.poweredOn ?? true
    /// 모니터 목록과 놓을 수 있는 자리. 모니터 구성이 바뀔 때만 다시 계산한다.
    @Published private(set) var screens: [ScreenInfo] = Layout.screens()
    @Published private(set) var placements: [Placement] = []
    /// 페어링 화면이 보이는 동안만 새 기기의 연결을 받는다
    var acceptingNewDevice = false { didSet { updateAcceptPolicy() } }

    /// Mac 조작 / 아이폰 조작 / 보정 중. InputRouter가 바꾼다.
    @Published var controlMode: ControlMode = .mac
    lazy var router = InputRouter(model: self)
    lazy var toasts = ToastCenter()
    lazy var dialogs = DialogPresenter(model: self)
    lazy var settingsWindow = SettingsWindowController(model: self)
    lazy var updater = Updater(model: self)

    private var bluetoothStarted = false
    private var pairer: Pairer?
    private var circleTimer: Timer?
    private var onboardingWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private var powerWatch: CBCentralManager?

    override init() {
        super.init()
        hid.delegate = self
        // 아이폰 쪽에서 연결해 올 때 받을 기기: 도우미가 바로 정해야 해서 규칙을 미리 넘겨 둔다
        updateAcceptPolicy()
        settings.$lastDeviceAddress.combineLatest(settings.$onlyDefaultDevice)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateAcceptPolicy() } }.store(in: &bag)
        // 하위 객체가 바뀌면 메뉴바 아이콘도 다시 그린다
        placements = Layout.placements(screens)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reloadScreens() }.store(in: &bag)
        // 잠자기: 설정에 따라 끊기 / 깨어남: 2초 뒤 기본 기기에 다시 연결 (설계 문서 › 상태와 예외 처리)
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            guard let self else { return }
            // 사용자가 직접 끊어둔 상태면 깨어나도 다시 연결하지 않는다
            self.reconnectAfterWake = self.isConnected || self.connectingAddress != nil
            guard self.settings.disconnectOnSleep else { return }
            self.router.returnToMac(.sleep)
            self.disconnect()
        }.store(in: &bag)
        ws.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.reconnectAfterWake, self.settings.onboardingDone, self.settings.autoReconnect,
                      !self.isConnected, let a = self.settings.lastDeviceAddress else { return }
                self.reconnectAfterWake = false
                if case .connecting = self.connection { return }
                self.connect(address: a)
            }
        }.store(in: &bag)
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

    private func trackConnection(from old: ConnectionPhase) {
        switch connection {
        case .connecting, .pairing:
            if connectingSince == nil { connectingSince = Date() }
        case .connected:
            connectingSince = nil
            failureStreak = 0
            disconnectedByUser = false
        case .failed:
            connectingSince = nil
            if old != connection { failureStreak += 1 }
        case .idle:
            connectingSince = nil
        }
    }

    /// 개발용 화면 캡처에서만: 연결 상태를 흉내 낸다
    func debugSetConnection(_ phase: ConnectionPhase, failureStreak streak: Int = 0) {
        guard Snapshot.directory != nil else { return }
        connection = phase
        failureStreak = streak
    }

    // MARK: 화면 사이 연결 (Contracts.swift)

    func openSettings(_ tab: SettingsTab = .general) {
        closeMenuBarPopover()
        settingsWindow.show(tab: tab)
    }

    /// 메뉴바 팝오버(MenuBarExtra 창)를 닫는다. 다른 창을 열 때 팝오버가 남아 있지 않게.
    func closeMenuBarPopover() {
        for w in NSApp.windows where w.isVisible && String(describing: Swift.type(of: w)).contains("MenuBarExtra") {
            w.close()
        }
    }
    func showToast(_ text: String, systemImage: String? = nil) { toasts.show(text, systemImage: systemImage) }
    /// 확인 창은 Mac에서 눌러야 하므로, 아이폰 조작 중이면 먼저 Mac으로 돌아온다
    func present(_ dialog: AppDialog) {
        closeMenuBarPopover()
        if controlMode != .mac { router.returnToMac(.menu) }
        dialogs.present(dialog)
    }

    /// 클립보드 보내기 (팝오버 버튼, ⌃⌥⌘V). 첫 사용이거나 영문 외 글자가 섞이면 확인 창부터.
    func requestClipboardSend() {
        guard settings.clipboardTypingAllowed else { return showToast("회사 정책으로 클립보드 보내기가 꺼져 있어요") }
        guard isConnected else { return showToast("아이폰이 연결되지 않았어요") }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else { return showToast("클립보드가 비어 있어요") }
        let sendable = text.filter { HIDUsage.fromASCII($0) != nil }.count
        let skipped = text.count - sendable
        if !settings.clipboardConfirmSkip || skipped > 0 {
            confirmedClipboardChange = NSPasteboard.general.changeCount
            present(.clipboardConfirm(sendable: sendable, skipped: skipped))
        } else {
            router.typeClipboard()
        }
    }

    /// 확인 창에서 "보내기"를 눌렀을 때
    func confirmClipboardSend(dontAskAgain: Bool) {
        if dontAskAgain { settings.clipboardConfirmSkip = true }
        // 확인 창을 띄운 뒤 클립보드가 바뀌었으면 확인하지 않은 내용을 보내지 않는다
        guard NSPasteboard.general.changeCount == confirmedClipboardChange else {
            showToast("클립보드가 바뀌어서 보내지 않았어요")
            return
        }
        router.typeClipboard()
    }

    private var confirmedClipboardChange = -1
    private var reconnectAfterWake = false
    private let hangWatch = HangWatch()
    /// 연결 요청 확인 창을 띄운 시각 (같은 기기가 5분 안에 다시 시도하면 묻지 않고 거절)
    private var connectionPrompts: [String: Date] = [:]

    /// 연결 요청 확인 창에서 허용: 그 기기를 새 기본 기기로 정하고 연결한다
    func acceptConnectionRequest(address: String, name: String) {
        connectionPrompts[address] = nil
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
        // 지운 기기로 다시 연결하지 않게: 재연결 예약 취소, 기본 주소 지우기, 연결 기다리기 멈춤
        hid.defaultAddress = nil
        hid.cancelReconnect()
        stopBluetooth()
        openOnboarding(at: .welcome)
    }
    var connectedName: String? { if case let .connected(name) = connection { return name } else { return nil } }

    // MARK: 시작 · 종료

    func launch() {
        if Snapshot.directory != nil { return Snapshot.run(model: self) }
        // 연결 로그를 파일로도 남긴다 (문제를 살펴볼 때 씀, 주소 뒷자리는 가림)
        HIDLog.fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/EdgeLink/EdgeLink.log")
        HIDLog.info("EdgeLink 시작 (\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))")
        hangWatch.start()
        // 설정 창의 ⌘, 키 감시가 첫 실행부터 동작하게 미리 만든다
        _ = settingsWindow
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
        updater.startAutomaticChecks()
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
        hid.shutdown()
    }

    /// 기본 기기만 받는다. 페어링 화면이 보이는 동안이나 "기본 기기만 연결 허용"을 끄면 누구든 받는다.
    private func updateAcceptPolicy() {
        hid.acceptPolicy = .init(address: settings.lastDeviceAddress,
                                 acceptAll: acceptingNewDevice || !settings.onlyDefaultDevice)
    }

    /// 블루투스는 온보딩 2단계(권한) 전에는 쓰지 않는다. 설명 없이 시스템 창이 먼저 뜨지 않게.
    func startBluetoothIfAllowed() {
        // 화면 캡처 중엔 블루투스를 쓰지 않는다 (실제 아이폰에 연결을 시도했었음)
        guard Snapshot.directory == nil else { return }
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
        disconnectedByUser = false
        connectingAddress = address
        let paired = IOBluetoothDevice(addressString: address)?.isPaired() ?? false
        if paired {
            connection = .connecting
            hid.resetReconnectPolicy()  // 직접 다시 연결하면 다음 자동 시도는 15초부터
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
                HIDLog.error("페어링 실패: \(BluetoothHID.describe(result))")
                self.connection = .failed(message: "페어링하지 못했어요 (\(BluetoothHID.describe(result)))")
            }
        }
        pairer = p
        connection = .pairing(code: nil)
        let r = p.start(address: address)
        if r != kIOReturnSuccess {
            HIDLog.error("페어링 시작 실패: \(BluetoothHID.describe(r))")
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

    /// 팝오버 기기 메뉴의 "연결 끊기", 연결 중 "취소". 다시 연결할 때까지 자동으로 붙지 않는다.
    func disconnectByUser(toast: String = "연결을 끊었어요. 다시 연결하려면 메뉴 막대 아이콘을 누르세요") {
        disconnect()
        disconnectedByUser = true
        showToast(toast)
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
        closeMenuBarPopover()
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

extension AppModel: HIDHelperClientDelegate {
    func hid(_ hid: HIDHelperClient, didChange state: BluetoothHID.State) {
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
            disconnectedAt = nil
            connection = .connected(name: name)
        case let .disconnected(reason):
            stopCircleIfNeeded()
            router.returnToMac(.disconnected)
            if reason == .rejected { return }  // 기본 기기 상태와 상관없는 거절
            // 재연결이 실패해도 처음 끊긴 시각을 유지한다 (연결되면 지움)
            if reason != .user, disconnectedAt == nil { disconnectedAt = Date() }
            switch reason {
            case .user: connection = .idle
            case let .openFailed(stage, code):
                connection = .failed(message: "\(stage) 실패 (\(BluetoothHID.describe(code)))")
            case .rejected: break  // 위에서 이미 처리
            case .virtualCableUnplug: connection = .failed(message: "아이폰에서 연결을 해제했어요")
            case .channelClosed, .stalled: connection = .failed(message: "연결이 끊겼어요")
            case .helperLost: connection = .failed(message: "연결이 끊겼어요")
            }
        }
    }

    /// 허용하지 않은 기기가 연결해 와서 도우미가 채널을 닫았다. 확인 창을 띄우고, 허용하면 그 기기로 Mac이 먼저 연결한다.
    func hid(_ hid: HIDHelperClient, didRejectIncoming address: String, name: String) {
        let name = name.isEmpty ? (address.isEmpty ? "이름 없는 기기" : address) : name
        if let asked = connectionPrompts[address], Date().timeIntervalSince(asked) < 300 {
            HIDLog.info("최근에 물어본 기기라 조용히 거절")
            return
        }
        connectionPrompts[address] = Date()
        present(.connectionRequest(name: name, address: address))
    }

    /// 블루투스 쓰기가 3번 연속 50ms를 넘거나 도우미가 응답하지 않으면 Mac으로 돌아온다
    func hidTransportStalled(_ hid: HIDHelperClient) {
        router.returnToMac(.transportStalled)
    }

    /// SDP 등록 실패 등
    func hid(_ hid: HIDHelperClient, didFail message: String) {
        connection = .failed(message: message)
    }

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
        HStack(spacing: 4) {
            Image(nsImage: Self.image(symbol: symbol, warning: warning))
            if settings.showDeviceNameInMenuBar, let name = model.connectedName {
                Text(name)
            }
        }
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

    /// 연결 안 됨 · 연결됨(Mac 조작 중) · 아이폰 조작 중 (설계 문서 › 메뉴바 아이콘). 경고는 주황 점.
    private var symbol: String {
        guard model.isConnected else { return "iphone.slash" }
        return model.controlMode == .mac ? "iphone" : "iphone.radiowaves.left.and.right"
    }

    private var label: String {
        if warning { return "EdgeLink · 문제 있음" }
        if model.isConnected, model.controlMode != .mac { return "EdgeLink · 아이폰 조작 중" }
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
