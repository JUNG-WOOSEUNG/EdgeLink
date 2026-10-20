import AppKit
import Carbon.HIToolbox
import Combine
import EdgeLinkCore
import IOKit

/// 입력은 CGEventTap 하나로 받고, 모드에 따라 Mac에 그대로 보내거나 막고 HID 리포트로 바꿔 아이폰에 보낸다.
///
/// 스레드
/// - 이벤트 탭은 전용 스레드의 런루프에서 돈다. 메인 스레드가 바빠도 Mac 입력이 늦어지지 않게.
/// - 탭 콜백과 메인 스레드가 같이 쓰는 상태(`st`)는 `lock`으로 지킨다. 콜백은 잠깐 잡고 바로 놓는다.
/// - 블루투스 쓰기는 `hid`의 직렬 큐가 한다(`hid` 메서드는 어느 스레드에서 불러도 됨).
/// - 커서·창·설정·알림은 메인 스레드에서만 바꾼다.
///
/// 안전 규칙
/// - Mac 조작 중에는 이벤트를 삼키지 않는다. 예외는 등록한 단축키의 누름·뗌, 아이폰 조작 중 누른 키·버튼이
///   돌아온 뒤 뒤늦게 떼지는 것(Mac에는 누름이 간 적이 없음)뿐이다.
/// - 탭을 못 만들거나 꺼지면 넘어가지 않는다. 아이폰 조작 중에 꺼지면 바로 돌아온다.
/// - ⌃⌥⌘Space는 아이폰 조작·보정 중 언제나 Mac으로 돌아온다 (설정에서 바꿔도 이 조합은 남는다).
final class InputRouter {
    unowned let model: AppModel
    /// 온보딩 연습 단계 자동 체크용
    let practice = PassthroughSubject<PracticeEvent, Never>()

    // 탭 스레드와 같이 쓰는 상태
    private let lock = NSLock()
    private var st = TapState()

    // 메인 스레드 전용
    private let glow = EdgeGlow()
    private var bag = Set<AnyCancellable>()
    private var watchdog: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var cursorFrozen = false
    private var cursorHidden = false
    private var calibrationUpdate: ((CalibrationEvent) -> Void)?
    private var configScheduled = false

    private let timerQueue = DispatchQueue(label: "com.edgelink.router.timer", qos: .userInteractive)

    /// ⌃⌥⌘Space — 어떤 상태에서도 Mac으로 돌아오는 조합
    private static let safetyCombo = KeyCombo(keyCode: 0x31, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)

    init(model: AppModel) {
        self.model = model
        recoverAfterCrash()
        observeSystem()
        installSignalHandlers()
    }

    // MARK: - 시작 · 멈춤

    /// 권한(손쉬운 사용·입력 모니터링)이 있을 때 이벤트 탭을 만든다. 여러 번 불러도 된다.
    func start() {
        rebuildConfig()
        lock.lock()
        if let tap = st.tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            lock.unlock()
            return
        }
        guard !st.starting else { lock.unlock(); return }
        st.starting = true
        st.stopRequested = false
        lock.unlock()

        let thread = Thread { [weak self] in self?.runTapThread() }
        thread.name = "EdgeLink 입력 감시"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        lock.lock()
        let wasRemote = st.mode != .mac
        lock.unlock()
        if wasRemote { returnToMac(.permissionLost) }
        // 종료 직전에도 불리므로, 비동기 마무리를 기다리지 않고 커서와 상태를 지금 되돌린다
        restoreNowIfBackOnMac()

        lock.lock()
        st.stopRequested = true
        let tap = st.tap, source = st.tapSource, runLoop = st.tapRunLoop
        st.tap = nil; st.tapSource = nil; st.tapRunLoop = nil
        st.push?.reset()
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
        if tap != nil { HIDLog.info("입력 감시 멈춤") }
        // 앞에서 보낸 빈 리포트가 실제로 나가도록 전송 큐를 한 번 기다린다 (종료 직전 연결을 끊기 전에)
        _ = model.hid.writeStatistics()
    }

    private func runTapThread() {
        var mask: CGEventMask = 0
        for t in Self.eventTypes { mask |= CGEventMask(1) << CGEventMask(t) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: routerTapCallback, userInfo: me) else {
            lock.lock(); st.starting = false; lock.unlock()
            DispatchQueue.main.async { HIDLog.error("입력 감시를 시작하지 못했어요 (손쉬운 사용·입력 모니터링 권한 확인)") }
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.lock()
        st.starting = false
        if st.stopRequested {
            lock.unlock()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            return
        }
        st.tap = tap; st.tapSource = source; st.tapRunLoop = runLoop
        lock.unlock()
        DispatchQueue.main.async { HIDLog.info("입력 감시 시작") }
        CFRunLoopRun()
    }

    /// 키보드·마우스·스크롤·수정키·system-defined(14)·제스처 계열(18, 19, 20, 29, 30, 31, 32)
    private static let eventTypes: [UInt32] = [
        CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue,
        CGEventType.mouseMoved.rawValue,
        CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue, CGEventType.leftMouseDragged.rawValue,
        CGEventType.rightMouseDown.rawValue, CGEventType.rightMouseUp.rawValue, CGEventType.rightMouseDragged.rawValue,
        CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue, CGEventType.otherMouseDragged.rawValue,
        CGEventType.scrollWheel.rawValue,
        RawType.systemDefined,
    ] + RawType.gestures

    // MARK: - 전환 (공개)

    func enterPhone(_ reason: EnterReason) {
        lock.lock()
        let failure = beginEnterLocked(reason, macAlong: nil)
        lock.unlock()
        if let failure { showToast(failure) }
    }

    func returnToMac(_ reason: ReturnReason) {
        lock.lock()
        // 끊김은 설정 사본이 다시 만들어지기 전에 바로 반영해서, 그 틈에 넘어가지 않게
        if reason == .disconnected { st.config.connected = false }
        beginReturnLocked(reason)
        lock.unlock()
    }

    func toggle() {
        lock.lock()
        let mode = st.mode
        lock.unlock()
        if mode == .mac { enterPhone(.menu) } else { returnToMac(.menu) }
    }

    /// 아이폰 버튼 등록 도우미: 추가 버튼 n(4~8)을 한 번 누른다
    /// 아이폰은 포인터를 쓰고 있지 않을 때(Mac 조작 중) 들어온 버튼을 무시했다 (실기기 확인).
    /// 그래서 Mac 조작 중이면 아이폰 포인터를 살짝 움직여 깨운 뒤 누른다.
    func sendButton(_ n: Int) {
        guard model.isConnected else { return showToast("아이폰이 연결되지 않았어요") }
        guard (1...8).contains(n) else { return }
        lock.lock()
        let onMac = st.mode == .mac
        lock.unlock()
        if onMac {
            model.hid.move(dx: 2, dy: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { self.model.hid.move(dx: -2, dy: 0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.model.hid.click(button: n)
                HIDLog.info("추가 버튼 \(n) 보냄 (포인터 깨운 뒤)")
            }
        } else {
            model.hid.click(button: n)
            HIDLog.info("추가 버튼 \(n) 보냄")
        }
    }

    // MARK: - 넘어가기 · 돌아오기 (lock을 잡은 채 부른다, 어느 스레드든)

    /// 넘어가지 못하면 알림 문구를 돌려준다. 이미 아이폰 조작 중이면 아무것도 하지 않는다.
    private func beginEnterLocked(_ reason: EnterReason, macAlong: Double?) -> String? {
        guard st.mode == .mac else { return nil }
        let c = st.config
        guard st.tap != nil else { return "권한이 꺼져 있어서 넘어갈 수 없어요" }
        guard c.connected else { return "아이폰이 연결되지 않았어요" }
        guard c.mayEnter else { return "설정을 마치면 넘어갈 수 있어요" }
        guard let p = c.placement else { return "아이폰을 놓을 모서리가 없어요" }
        // 비밀번호 입력 중이면 넘어가지 않는다 (넘어가기 직전 확인)
        guard !IsSecureEventInputEnabled() else { return "Mac에서 비밀번호를 입력 중이라 넘어갈 수 없어요" }

        let surface = c.surface(p)
        let along = macAlong ?? (p.glow.passage.start + p.glow.passage.end) / 2
        let fraction = surface.phoneFraction(macAlong: along)
        // 모서리로 넘어가면 진입 모서리 바로 안쪽, 단축키·메뉴면 화면 가운데에 놓는다
        // (모서리에 두면 넘어가자마자 조금만 움직여도 "모서리로 밀었다"고 보고 돌아왔음)
        let depthPoints = reason == .edge ? EntryPlan.insetPoints : EntryPlan.centerDepthPoints(surface)
        let plan = EntryPlan.moves(surface: surface, phoneFraction: fraction, depthPoints: depthPoints)

        var session = PhoneSession(placement: p, enterReason: reason, glowAlong: along)
        session.pointer = EntryPlan.pointerAfter(surface: surface, phoneFraction: fraction, depthPoints: depthPoints)
        session.savedCursor = CGEvent(source: nil)?.location
        session.capsLockAtEntry = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        // 넘어가는 순간 Mac에서 눌려 있던 키: 그 키의 뗌은 Mac에 보낸다 (단축키 키는 따로 삼킨다)
        var held = Set<UInt16>()
        for code in 0..<UInt16(128) where CGEventSource.keyState(.combinedSessionState, key: code) {
            held.insert(code)
        }
        held.subtract(st.swallowKeyUp)
        session.held.begin(held: held)
        session.scroll = ScrollConverter(invert: c.invertScroll, pointsPerNotch: c.scrollPointsPerNotch)
        // 넘어갈 때 Mac에서 눌려 있던 버튼: 그 뗌은 Mac에 보낸다
        session.macButtonsAtEntry = st.macButtons
        // 이동 계획을 다 보내고 조금 더 지날 때까지는 돌아오지 않는다
        session.returnGuardUntil = ProcessInfo.processInfo.systemUptime + Double(plan.count) * 0.008 + 0.15

        st.mode = .phone
        st.generation += 1
        st.session = session
        st.push?.reset()
        startPlanLocked(plan)
        let gen = st.generation
        DispatchQueue.main.async { self.completeEnter(gen: gen, reason: reason, placement: p, along: along, calibrating: false) }
        return nil
    }

    /// 돌아오기. Mac 조작 중이면 아무것도 하지 않는다.
    private func beginReturnLocked(_ reason: ReturnReason) {
        guard st.mode != .mac else { return }
        let session = st.session
        let wasCalibrating = st.mode == .calibrating
        var point: CGPoint?
        if reason != .screensChanged, let session {
            if let pointer = session.pointer, reason == .edge || session.enterReason == .edge {
                // 같은 비율 높이, 모서리에서 24pt 안쪽
                let r = pointer.returnPoint(screen: session.placement.glow.screen)
                point = CGPoint(x: r.x, y: ScreenCoordinates.quartzY(cocoaY: r.y, mainHeight: st.config.mainHeight))
            } else {
                point = session.savedCursor
            }
        }
        let glowAlong = session?.pointer?.macAlong ?? session?.glowAlong ?? 0

        stopPlanLocked()
        // 메인 스레드가 막혀 있어도 커서는 바로 움직이게 (숨김 해제와 위치는 메인에서)
        CGAssociateMouseAndMouseCursorPosition(1)
        // 눌린 키와 버튼을 모두 뗀 상태로
        model.hid.sendEmptyReports()
        // 아이폰 조작 중 누른 키·버튼이 Mac 조작으로 돌아온 뒤 떼지면 Mac에는 보내지 않는다
        if let session {
            st.swallowKeyUp.formUnion(session.phoneCodes)
            st.swallowMouseUp |= session.macButtons
        }

        let outcome = st.calibration?.outcome
        st.calibration = nil
        st.mode = .mac
        st.generation += 1
        st.session = nil
        st.push?.reset()
        let info = ReturnInfo(reason: reason, point: point, placement: session?.placement, glowAlong: glowAlong,
                              wasCalibrating: wasCalibrating, calibration: outcome, capsLockAtEntry: session?.capsLockAtEntry)
        DispatchQueue.main.async { self.completeReturn(info) }
    }

    // MARK: - 넘어가기 · 돌아오기 마무리 (메인)

    private func completeEnter(gen: Int, reason: EnterReason, placement: PlacementInfo, along: Double, calibrating: Bool) {
        lock.lock()
        let current = st.generation == gen && st.mode != .mac
        let glass = st.config.glass
        lock.unlock()
        guard current else { return }
        freezeCursor(at: placement.centerQuartz)
        // 절전(App Nap)이 타이머를 묶어 움직임 전송이 30~60ms씩 늦어지던 것을 막는다
        if latencyActivity == nil {
            latencyActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                reason: "아이폰 조작 중 입력 전달")
        }
        model.settings.remoteActive = true
        model.controlMode = calibrating ? .calibrating : .phone
        startWatchdog()
        guard !calibrating else {
            HIDLog.info("보정 시작")
            return
        }
        if glass { glow.enter(along: along, at: placement.glow) }
        playSound(entering: true)
        HIDLog.info("아이폰 조작 시작 (\(reason.logLabel))")
        switch reason {
        case .edge: practice.send(.enteredByEdge)
        case .hotkey: practice.send(.toggledByHotkey)
        case .menu: break
        }
    }

    private func completeReturn(_ info: ReturnInfo) {
        lock.lock()
        let backOnMac = st.mode == .mac
        let glass = st.config.glass
        lock.unlock()
        // 그 사이 다시 넘어갔으면 커서는 새 상태가 맡는다
        if backOnMac {
            unfreezeCursor(warpTo: info.point)
            if let a = latencyActivity { ProcessInfo.processInfo.endActivity(a); latencyActivity = nil }
            model.settings.remoteActive = false
            model.controlMode = .mac
            stopWatchdog()
        }
        restoreCapsLock(info.capsLockAtEntry)

        if info.wasCalibrating {
            var result = info.calibration ?? .cancelled
            // 사용자가 멈춘 게 아니라 연결이 끊기거나 권한·화면이 바뀌어서 끝났으면 실패로 알린다
            if result == .cancelled {
                switch info.reason {
                case .disconnected: result = .failed(reason: "아이폰 연결이 끊겼어요")
                case .permissionLost: result = .failed(reason: "권한이 꺼졌어요")
                case .screensChanged: result = .failed(reason: "모니터 구성이 바뀌었어요")
                case .transportStalled, .tapDisabled: result = .failed(reason: "잠깐 멈춰서 보정을 끝냈어요")
                case .screenLocked, .sleep: result = .failed(reason: "화면이 잠겨서 보정을 끝냈어요")
                case .secureInput: result = .failed(reason: "비밀번호 입력이 시작돼서 보정을 끝냈어요")
                default: break
                }
            }
            if case let .finished(raw) = result, raw < 0.2 {
                result = .failed(reason: "움직인 양이 너무 작아요")
            }
            if case let .finished(raw) = result {
                let v = min(4.0, max(0.6, raw))  // 보정값 범위 0.6~4.0
                result = .finished(unitsPerPoint: v)
                model.settings.unitsPerPointValue = v
                HIDLog.info(String(format: "보정 완료 (%.2f)", v))
            } else {
                HIDLog.info("보정 끝 (저장하지 않음)")
            }
            let update = calibrationUpdate
            calibrationUpdate = nil
            update?(result)
            glow.hide()
            if let text = info.reason.toast { showToast(text, systemImage: "arrow.uturn.backward") }
            return
        }

        if let placement = info.placement, info.reason != .screensChanged, glass {
            glow.returned(along: info.glowAlong, at: placement.glow)
        } else {
            glow.hide()
        }
        playSound(entering: false)
        HIDLog.info("Mac 조작으로 돌아옴 (\(info.reason.logLabel))")
        if let text = info.reason.toast { showToast(text, systemImage: "arrow.uturn.backward") }
        switch info.reason {
        case .edge: practice.send(.returnedByEdge)
        case .hotkey: practice.send(.toggledByHotkey)
        default: break
        }
    }

    // MARK: - 커서

    private func freezeCursor(at center: CGPoint) {
        BackgroundCursor.enableOnce()
        CGWarpMouseCursorPosition(center)
        CGAssociateMouseAndMouseCursorPosition(0)
        cursorFrozen = true
        if !cursorHidden {
            CGDisplayHideCursor(CGMainDisplayID())
            cursorHidden = true
        }
    }

    private func unfreezeCursor(warpTo point: CGPoint?) {
        if let point { CGWarpMouseCursorPosition(point) }
        CGAssociateMouseAndMouseCursorPosition(1)
        cursorFrozen = false
        if cursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            cursorHidden = false
        }
    }

    /// 돌아오기 마무리(completeReturn)가 아직 안 돌았어도 커서·상태를 바로 되돌린다 (메인).
    private func restoreNowIfBackOnMac() {
        lock.lock()
        let mac = st.mode == .mac
        lock.unlock()
        guard mac else { return }
        if cursorFrozen || cursorHidden { unfreezeCursor(warpTo: nil) }
        if model.settings.remoteActive { model.settings.remoteActive = false }
        if model.controlMode != .mac { model.controlMode = .mac }
    }

    /// 지난 실행이 아이폰 조작 중에 끝났으면 커서를 풀고 빈 리포트를 보낸다.
    private func recoverAfterCrash() {
        guard model.settings.remoteActive else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        CGDisplayShowCursor(CGMainDisplayID())
        model.hid.sendEmptyReports()
        model.settings.remoteActive = false
        HIDLog.warn("지난 실행이 아이폰 조작 중에 끝나서 커서를 되돌렸어요")
    }

    /// SIGTERM·SIGINT: 커서를 되돌리고 빈 리포트를 보낸 뒤 정상 종료 절차로
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { exit(0) }
                HIDLog.info("종료 신호를 받았어요")
                self.returnToMac(.menu)
                CGAssociateMouseAndMouseCursorPosition(1)
                if self.cursorHidden { CGDisplayShowCursor(CGMainDisplayID()); self.cursorHidden = false }
                self.model.settings.remoteActive = false
                self.model.hid.sendEmptyReports()
                _ = self.model.hid.writeStatistics()
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - 시스템 상태 감시

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.returnToMac(.sleep) }.store(in: &bag)
        ws.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.returnToMac(.sleep) }.store(in: &bag)
        ws.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .sink { [weak self] _ in self?.returnToMac(.screenLocked) }.store(in: &bag)
        let dist = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            dist.publisher(for: Notification.Name(name))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.returnToMac(.screenLocked) }.store(in: &bag)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                // 효과 없이 돌아오고, 통로는 AppModel이 다시 계산한 뒤 설정을 다시 읽는다
                self?.returnToMac(.screensChanged)
                self?.scheduleConfig()
            }.store(in: &bag)
        // 설정·연결·배치가 바뀌면 탭 스레드가 읽는 값을 다시 만든다
        model.settings.objectWillChange.sink { [weak self] _ in self?.scheduleConfig() }.store(in: &bag)
        model.objectWillChange.sink { [weak self] _ in self?.scheduleConfig() }.store(in: &bag)
    }

    /// 아이폰 조작 중 0.25초마다: 비밀번호 입력, 탭 상태
    private var watchTicks = 0
    /// 아이폰 조작 중 절전 막기
    private var latencyActivity: NSObjectProtocol?

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.watch() }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func watch() {
        lock.lock()
        let remote = st.mode != .mac
        let tap = st.tap
        watchTicks += 1
        let moves = watchTicks % 8 == 0 ? st.moveEvents.take() : nil
        lock.unlock()
        // 2초마다 움직임 진단 (움직였을 때만): Mac 쪽 이벤트 간격과 블루투스 전송 간격을 같이 남긴다
        if let moves, moves.count > 10, let send = model.hid.takeMotionDiagnostics() {
            HIDLog.info("이동 진단 · Mac 이벤트 \(moves) | 전송 \(send.sends) | 쪼갬 최대 \(send.maxSplit) · 쓰기 최대 \(String(format: "%.1f", send.maxWriteMs))ms")
        }
        guard remote else { return stopWatchdog() }
        if IsSecureEventInputEnabled() { return returnToMac(.secureInput) }
        if !model.isConnected { return returnToMac(.disconnected) }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            return returnToMac(.tapDisabled)
        }
        if tap == nil { returnToMac(.permissionLost) }
    }

    // MARK: - 설정 사본

    private func scheduleConfig() {
        guard !configScheduled else { return }
        configScheduled = true
        // objectWillChange는 값이 바뀌기 전에 오므로 다음 차례에 읽는다
        DispatchQueue.main.async {
            self.configScheduled = false
            self.rebuildConfig()
        }
    }

    private func rebuildConfig() {
        let s = model.settings
        var c = RouterConfig()
        c.connected = model.isConnected
        c.mayEnter = s.onboardingDone || s.onboardingStep >= OnboardingStep.test.rawValue
        c.edgeEnabled = s.edgeEnabled
        c.glass = s.glassEnabled
        c.dragLock = s.dragLock
        c.invertScroll = s.invertScroll
        c.scrollPointsPerNotch = ScrollConverter.pointsPerNotch(speed: s.scrollSpeed)
        c.pointerScale = PointerScale.scale(unitsPerPoint: s.unitsPerPoint, speed: s.pointerSpeed)
        c.capsLockHangul = s.capsLockHangul
        c.mediaKeysToPhone = s.mediaKeysToPhone
        c.padShortcuts = s.profile.model.isPad && s.padUsesShortcuts
        c.hotkeys = s.hotkeys.mapValues { KeyCombo(keyCode: $0.keyCode, modifiers: $0.modifiers) }
        c.gestures = s.gestureMap
        let size = s.profile.model.screenSize
        (c.phoneWidth, c.phoneHeight) = s.profile.landscape ? (size.height, size.width) : (size.width, size.height)
        let k = s.unitsPerPoint
        c.unitsPerPoint = k.isFinite && k > 0 ? min(max(k, Calibration.range.lowerBound), Calibration.range.upperBound) : 2.0
        c.mainHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
        // 저장한 자리가 없으면 임시로 다른 빈 모서리 (저장 값은 그대로)
        if let p = model.currentPlacement ?? Layout.defaultPlacement(model.placements) {
            let f = p.screen.frame
            c.placement = PlacementInfo(
                glow: GlowPlacement(screen: f, edge: p.edge, passage: p.passage),
                threshold: LayoutGeometry.pushThreshold(sensitivity: s.sensitivity, sharesDockOrMenuBar: Layout.conflict(p) != nil),
                centerQuartz: CGPoint(x: f.x + f.width / 2,
                                      y: ScreenCoordinates.quartzY(cocoaY: f.y + f.height / 2, mainHeight: c.mainHeight)))
        }

        lock.lock()
        st.config = c
        if let p = c.placement {
            let pc = EdgePush.Config(screen: p.glow.screen, edge: p.glow.edge, passage: p.glow.passage,
                                     threshold: p.threshold, dragLock: c.dragLock)
            if st.push?.config != pc { st.push = EdgePush(config: pc) }
        } else {
            st.push = nil
        }
        lock.unlock()
    }

    // MARK: - 이벤트 처리 (탭 스레드)

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let raw = type.rawValue
        if raw == CGEventType.tapDisabledByTimeout.rawValue || raw == CGEventType.tapDisabledByUserInput.rawValue {
            // 즉시 다시 켜고, 아이폰 조작 중이었으면 돌아온다
            lock.lock()
            if let tap = st.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let remote = st.mode != .mac
            if remote { beginReturnLocked(.tapDisabled) }
            lock.unlock()
            DispatchQueue.main.async { HIDLog.warn("입력 감시가 꺼져서 다시 켰어요") }
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let pass: Bool
        if st.mode == .mac {
            pass = handleMac(raw, event)
        } else {
            pass = handleRemote(raw, event)
        }
        lock.unlock()
        return pass ? Unmanaged.passUnretained(event) : nil
    }

    // MARK: Mac 조작 중 — 단축키 말고는 모두 그대로 통과

    private func handleMac(_ raw: UInt32, _ event: CGEvent) -> Bool {
        switch raw {
        case CGEventType.keyDown.rawValue:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if st.swallowKeyUp.contains(code) {
                if isRepeat { return false }          // 단축키를 누른 채 반복
                st.swallowKeyUp.remove(code)          // 새로 누름이면 남은 기록은 버린다
            }
            if code == ModifierKeys.escapeKeyCode, !isRepeat, st.typing != nil { st.typing?.stop = true }
            guard !isRepeat, let action = matchHotkeyLocked(code, event.flags.rawValue, gestures: false),
                  [.toggleRemote, .sendClipboard, .toggleEdge].contains(action) else { return true }
            // 단축키의 뗌·반복도 Mac에 보내지 않는다 (넘어가기 전에 적어 둬야 넘어갈 때 눌린 키에서 빠진다)
            st.swallowKeyUp.insert(code)
            switch action {
            case .toggleRemote:
                if let failure = beginEnterLocked(.hotkey, macAlong: nil) { showToast(failure) }
            case .sendClipboard:
                DispatchQueue.main.async { self.model.requestClipboardSend() }
            case .toggleEdge:
                DispatchQueue.main.async { self.toggleEdge() }
            default:
                break
            }
            return false

        case CGEventType.keyUp.rawValue:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return st.swallowKeyUp.remove(code) == nil

        case CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue,
             CGEventType.rightMouseDragged.rawValue, CGEventType.otherMouseDragged.rawValue:
            detectPushLocked(event, dragging: raw != CGEventType.mouseMoved.rawValue)
            return true

        case CGEventType.leftMouseDown.rawValue, CGEventType.rightMouseDown.rawValue, CGEventType.otherMouseDown.rawValue:
            let bit = Self.buttonBit(event)
            st.macButtons |= bit
            st.swallowMouseUp &= ~bit
            return true

        case CGEventType.leftMouseUp.rawValue, CGEventType.rightMouseUp.rawValue, CGEventType.otherMouseUp.rawValue:
            let bit = Self.buttonBit(event)
            st.macButtons &= ~bit
            if st.swallowMouseUp & bit != 0 {
                st.swallowMouseUp &= ~bit
                return false
            }
            return true

        default:
            return true
        }
    }

    private func detectPushLocked(_ event: CGEvent, dragging: Bool) {
        let c = st.config
        guard c.edgeEnabled, c.connected, c.mayEnter, var push = st.push, let p = c.placement else { return }
        let loc = event.location
        let x = Double(loc.x), y = ScreenCoordinates.cocoaY(quartzY: Double(loc.y), mainHeight: c.mainHeight)
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = -event.getDoubleValueField(.mouseEventDeltaY)   // Quartz는 아래가 +
        let r = push.update(x: x, y: y, dx: dx, dy: dy, buttonsDown: dragging || st.macButtons != 0,
                            time: ProcessInfo.processInfo.systemUptime)
        st.push = push
        switch r {
        case let .pushing(progress, along):
            requestGlowLocked(progress: progress, along: along, placement: p)
        case let .crossed(along, _):
            if let failure = beginEnterLocked(.edge, macAlong: along) { showToast(failure) }
        case .none, .blockedByDrag:
            break
        }
    }

    // MARK: 아이폰 조작 · 보정 중 — Mac으로 가는 입력을 막고 HID로

    private func handleRemote(_ raw: UInt32, _ event: CGEvent) -> Bool {
        let calibrating = st.mode == .calibrating
        switch raw {
        case CGEventType.keyDown.rawValue:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let flags = event.flags.rawValue
            if st.swallowKeyUp.contains(code) {
                if isRepeat { return false }
                st.swallowKeyUp.remove(code)
            }
            if !isRepeat, let action = matchHotkeyLocked(code, flags, gestures: !calibrating) {
                st.swallowKeyUp.insert(code)
                runRemoteHotkeyLocked(action, calibrating: calibrating)
                return false
            }
            if calibrating {
                if code == ModifierKeys.escapeKeyCode, !isRepeat {
                    st.calibration?.outcome = .cancelled
                    beginReturnLocked(.menu)
                    st.swallowKeyUp.insert(code)
                }
                return false
            }
            if st.typing != nil {
                if code == ModifierKeys.escapeKeyCode, !isRepeat { st.typing?.stop = true }
                return false
            }
            guard var s = st.session else { return false }
            if s.held.keyDown(code, isRepeat: isRepeat) == .phone, let usage = HIDUsage.fromMacKeyCode(code) {
                s.phoneCodes.insert(code)
                if let r = s.keys.press(usage) { model.hid.send(r) }
            }
            st.session = s
            return false

        case CGEventType.keyUp.rawValue:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if st.swallowKeyUp.remove(code) != nil { return false }
            guard var s = st.session else { return false }
            if s.held.keyUp(code) == .mac {
                st.session = s
                return true                            // 넘어가기 전부터 눌려 있던 키의 뗌
            }
            s.phoneCodes.remove(code)
            if let usage = HIDUsage.fromMacKeyCode(code), let r = s.keys.release(usage), !calibrating, st.typing == nil {
                model.hid.send(r)
            }
            st.session = s
            return false

        case CGEventType.flagsChanged.rawValue:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            guard var s = st.session else { return false }
            let quiet = calibrating || st.typing != nil
            if code == ModifierKeys.capsLockKeyCode {
                if !quiet {
                    // 실제 키보드처럼 신호 사이에 20ms를 둔다 (붙여 보내면 아이폰이 ⌃Space를 놓쳤음)
                    model.hid.send(CapsLockRule.reports(hangul: st.config.capsLockHangul, current: s.keys.report), gap: 0.02)
                }
                return false
            }
            // Fn·Globe: 아이폰에 보내지 않고, 받아쓰기·이모지 창이 뜨지 않게 Mac에서도 막는다
            if code == ModifierKeys.fnKeyCode {
                // 넘어가기 전부터 눌려 있던 Fn의 뗌만 Mac으로
                let pressed = ModifierKeys.isPressed(keyCode: code, flags: event.flags.rawValue) ?? false
                let route = s.held.modifier(code, pressed: pressed)
                st.session = s
                return route == .mac
            }
            guard let pressed = ModifierKeys.isPressed(keyCode: code, flags: event.flags.rawValue) else { return false }
            if s.held.modifier(code, pressed: pressed) == .mac {
                st.session = s
                return true
            }
            guard let usage = HIDUsage.fromMacKeyCode(code) else { st.session = s; return false }
            if pressed {
                // 수정키는 phoneCodes에 넣지 않는다 (뗌이 flagsChanged라서 삼킬 필요가 없고, 넣으면 다음 넘어가기 때 눌린 키 기록에서 빠진다)
                if !quiet, let r = s.keys.press(usage) { model.hid.send(r) }
            } else {
                if let r = s.keys.release(usage), !quiet { model.hid.send(r) }
            }
            st.session = s
            return false

        case CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue,
             CGEventType.rightMouseDragged.rawValue, CGEventType.otherMouseDragged.rawValue:
            guard var s = st.session else { return false }
            st.moveEvents.tick()
            // 보정 중엔 1:1 (보정 도우미가 보낸 단위를 그대로 재야 해서)
            let k = calibrating ? 1.0 : st.config.pointerScale
            let m = s.remainder.take(dx: event.getDoubleValueField(.mouseEventDeltaX) * k,
                                     dy: event.getDoubleValueField(.mouseEventDeltaY) * k)
            st.session = s
            guard m.dx != 0 || m.dy != 0 else { return false }
            if calibrating {
                guard var cal = st.calibration, cal.ready else { return false }
                model.hid.move(dx: m.dx, dy: m.dy)
                cal.dx += m.dx; cal.dy += m.dy
                st.calibration = cal
                scheduleCalibrationMovedLocked()
                return false
            }
            model.hid.move(dx: m.dx, dy: m.dy)
            s.pointer?.move(dx: Double(m.dx), dy: Double(m.dy))
            st.session = s
            checkEdgeReturnLocked()
            return false

        case CGEventType.leftMouseDown.rawValue, CGEventType.rightMouseDown.rawValue, CGEventType.otherMouseDown.rawValue:
            let bit = Self.buttonBit(event)
            if calibrating {
                if raw == CGEventType.leftMouseDown.rawValue, let cal = st.calibration, cal.ready {
                    finishCalibrationLocked(cal)
                    st.swallowMouseUp |= bit
                }
                return false
            }
            st.swallowMouseUp &= ~bit
            guard var s = st.session else { return false }
            s.macButtonsAtEntry &= ~bit
            s.macButtons |= bit
            s.buttons |= UInt8(truncatingIfNeeded: bit)
            model.hid.setButtons(s.buttons)
            st.session = s
            return false

        case CGEventType.leftMouseUp.rawValue, CGEventType.rightMouseUp.rawValue, CGEventType.otherMouseUp.rawValue:
            let bit = Self.buttonBit(event)
            if st.swallowMouseUp & bit != 0 { st.swallowMouseUp &= ~bit; return false }
            guard var s = st.session else { return false }
            if s.macButtonsAtEntry & bit != 0 {
                // 넘어가기 전부터 눌려 있던 버튼의 뗌 → Mac으로 (드래그가 Mac에서 끝나게)
                s.macButtonsAtEntry &= ~bit
                st.macButtons &= ~bit
                st.session = s
                return true
            }
            s.macButtons &= ~bit
            s.buttons &= ~UInt8(truncatingIfNeeded: bit)
            if !calibrating { model.hid.setButtons(s.buttons) }
            st.session = s
            // 버튼을 누른 채 돌아오려 했으면 뗀 지금 돌아온다
            checkEdgeReturnLocked()
            return false

        case CGEventType.scrollWheel.rawValue:
            guard !calibrating, var s = st.session else { return false }
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let dy = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                                : event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let dx = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                                : event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let r = s.scroll.convert(deltaY: dy, deltaX: dx, continuous: continuous)
            st.session = s
            if r.wheel != 0 || r.pan != 0 { model.hid.scroll(wheel: r.wheel, pan: r.pan) }
            return false

        case RawType.systemDefined:
            return handleMediaKeyLocked(event, calibrating: calibrating)

        default:
            if RawType.gestures.contains(raw) {
                // 제스처는 Mac에 보내지 않는다. 손가락 이벤트(29)로 아이폰 동작을 알아낸다.
                if raw == RawType.gesture, !calibrating { recognizeGestureLocked(event) }
                return false
            }
            return true
        }
    }

    private func runRemoteHotkeyLocked(_ action: HotkeyAction, calibrating: Bool) {
        switch action {
        case .toggleRemote:
            if calibrating { st.calibration?.outcome = .cancelled }
            beginReturnLocked(calibrating ? .menu : .hotkey)
        case .sendClipboard:
            if !calibrating { DispatchQueue.main.async { self.model.requestClipboardSend() } }
        case .toggleEdge:
            DispatchQueue.main.async { self.toggleEdge() }
        default:
            if let g = action.gesture { performGestureLocked(g, viaHotkey: true) }
        }
    }

    /// 단축키 찾기. 아이폰 조작 중에는 ⌃⌥⌘Space가 늘 전환이고, 제스처 대체 단축키도 본다.
    private func matchHotkeyLocked(_ code: UInt16, _ flags: UInt64, gestures: Bool) -> HotkeyAction? {
        let c = st.config
        if st.mode != .mac, Self.safetyCombo.matches(keyCode: code, flags: flags) { return .toggleRemote }
        // 설정 창에서 단축키를 기록하는 중엔 Mac 조작 단축키를 처리하지 않는다 (안전 조합은 위에서 이미 처리)
        if HotkeyRecorderState.isRecording { return nil }
        for action in [HotkeyAction.toggleRemote, .sendClipboard, .toggleEdge] {
            if c.hotkeys[action]?.matches(keyCode: code, flags: flags) == true { return action }
        }
        guard gestures else { return nil }
        for g in PhoneGesture.allCases where (c.gestures[g] ?? GestureSetting.defaults[g])?.hotkeyEnabled == true {
            if c.hotkeys[g.hotkeyAction]?.matches(keyCode: code, flags: flags) == true { return g.hotkeyAction }
        }
        return nil
    }

    private func checkEdgeReturnLocked() {
        guard st.mode == .phone, st.config.edgeEnabled, let s = st.session, let pointer = s.pointer else { return }
        guard ProcessInfo.processInfo.systemUptime >= s.returnGuardUntil else { return }
        if pointer.shouldReturn(buttonsDown: s.buttons != 0) { beginReturnLocked(.edge) }
    }

    private func handleMediaKeyLocked(_ event: CGEvent, calibrating: Bool) -> Bool {
        // 미디어 키를 아이폰으로 보내지 않으면 내용을 볼 필요 없이 Mac에 그대로 둔다.
        // (NSEvent(cgEvent:)는 탭 스레드에서 만들면 안 된다: Caps Lock 처리 중 TSM이 메인 큐를 확인하다 앱이 꺼졌음)
        guard st.config.mediaKeysToPhone, !calibrating else { return true }
        guard let info = Self.systemDefinedInfoOnMain(event) else { return true }
        guard info.subtype == MediaKey.subtype else { return true }
        let m = MediaKey.parse(data1: info.data1)
        // 밝기는 항상 Mac
        if MediaKey.isBrightness(m.keyType) { return true }
        guard let usage = MediaKey.consumerUsage(m.keyType) else { return true }
        if m.down {
            if !m.isRepeat { model.hid.send(ConsumerReport(usage: usage)) }
        } else {
            model.hid.send(ConsumerReport(usage: 0))
        }
        return false
    }

    /// system-defined 이벤트의 subtype·data1을 메인 스레드에서 읽는다. 30ms 안에 못 읽으면 nil (그 키는 Mac에 둠).
    private static func systemDefinedInfoOnMain(_ event: CGEvent) -> (subtype: Int, data1: Int)? {
        guard let copy = event.copy() else { return nil }
        var result: (Int, Int)?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            if let ns = NSEvent(cgEvent: copy), ns.type == .systemDefined {
                result = (Int(ns.subtype.rawValue), ns.data1)
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + 0.03) == .success, let r = result else { return nil }
        return (subtype: r.0, data1: r.1)
    }

    /// 제스처는 아이폰 조작 중 늘 Mac에서 막으므로 바로 판단할 필요가 없다.
    /// 손가락 정보는 메인 스레드에서 NSEvent로 읽고, 결과만 잠금 안에서 반영한다.
    private func recognizeGestureLocked(_ event: CGEvent) {
        guard st.session != nil, let copy = event.copy() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let ns = NSEvent(cgEvent: copy), ns.type == .gesture else { return }
            let all = ns.allTouches()
            // 손가락 정보가 없는 제스처 이벤트(확대·회전 등)는 건너뛴다
            guard !all.isEmpty else { return }
            let touching = all.filter { !$0.phase.contains(.ended) && !$0.phase.contains(.cancelled) }
                .map { GestureRecognizer.Touch(x: Double($0.normalizedPosition.x), y: Double($0.normalizedPosition.y)) }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.st.mode == .phone, var s = self.st.session else { return }
            let found = s.gestures.update(touching)
            self.st.session = s
            guard let found else { return }
            let g: PhoneGesture
            switch found {
            case .threeFingerUp: g = .threeFingerUp
            case .threeFingerDown: g = .threeFingerDown
            case .fourFingerDown: g = .fourFingerDown
            case .fourFingerPinch: g = .fourFingerPinch
            }
            self.performGestureLocked(g, viaHotkey: false)
        }
    }

    /// 제스처 → 추가 버튼 클릭. 아이패드 옵션이면 홈은 ⌘H, 앱 전환기는 ⌘Tab.
    private func performGestureLocked(_ g: PhoneGesture, viaHotkey: Bool) {
        let c = st.config
        let setting = c.gestures[g] ?? GestureSetting.defaults[g]!
        guard viaHotkey ? setting.hotkeyEnabled : setting.gestureEnabled else { return }
        if c.padShortcuts, g == .fourFingerPinch || g == .threeFingerUp {
            let usage = g == .fourFingerPinch ? PadShortcut.home : PadShortcut.appSwitcher
            let restore = st.session?.keys.report ?? KeyboardReport()
            for r in PadShortcut.reports(usage: usage, restore: restore) { model.hid.send(r) }
        } else {
            model.hid.click(button: setting.button)
        }
        DispatchQueue.main.async { HIDLog.info("제스처 동작 보냄 (\(g.phoneAction))") }
    }

    static func buttonBit(_ event: CGEvent) -> UInt32 {
        let n = event.getIntegerValueField(.mouseEventButtonNumber)
        return (0..<8).contains(n) ? UInt32(1) << UInt32(n) : 0
    }

    // MARK: - 넘어가는 순간 이동 계획 (8ms마다)

    private func startPlanLocked(_ moves: [HIDMove]) {
        st.planTimer?.cancel()
        st.plan = moves
        st.planIndex = 0
        let gen = st.generation
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.planTick(gen) }
        st.planTimer = t
        t.resume()
    }

    private func stopPlanLocked() {
        st.planTimer?.cancel()
        st.planTimer = nil
        st.plan = []
        st.planIndex = 0
    }

    private func planTick(_ gen: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard st.generation == gen, st.mode != .mac, st.planIndex < st.plan.count else {
            if st.generation == gen { stopPlanLocked() }
            return
        }
        let m = st.plan[st.planIndex]
        st.planIndex += 1
        model.hid.move(dx: m.dx, dy: m.dy)
        guard st.planIndex >= st.plan.count else { return }
        stopPlanLocked()
        if st.mode == .calibrating, st.calibration != nil {
            st.calibration?.ready = true
            DispatchQueue.main.async { self.calibrationUpdate?(.ready) }
        }
    }

    // MARK: - 보정 도우미

    func startCalibration(_ update: @escaping (CalibrationEvent) -> Void) {
        guard model.isConnected else { return update(.failed(reason: "아이폰을 연결하면 쓸 수 있어요")) }
        rebuildConfig()
        lock.lock()
        guard st.tap != nil else {
            lock.unlock()
            return update(.failed(reason: "권한이 꺼져 있어서 쓸 수 없어요"))
        }
        guard st.mode != .calibrating else {
            lock.unlock()
            return update(.failed(reason: "이미 보정 중이에요"))
        }
        let c = st.config
        guard let p = c.placement else {
            lock.unlock()
            return update(.failed(reason: "아이폰을 놓을 모서리가 없어요"))
        }
        calibrationUpdate = update
        let fromMac = st.mode == .mac
        if fromMac {
            var session = PhoneSession(placement: p, enterReason: .menu, glowAlong: (p.glow.passage.start + p.glow.passage.end) / 2)
            session.savedCursor = CGEvent(source: nil)?.location
            session.capsLockAtEntry = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
            var held = Set<UInt16>()
            for code in 0..<UInt16(128) where CGEventSource.keyState(.combinedSessionState, key: code) { held.insert(code) }
            held.subtract(st.swallowKeyUp)
            session.held.begin(held: held)
            session.macButtonsAtEntry = st.macButtons
            st.session = session
            st.generation += 1
        } else {
            // 아이폰 조작 중에 열었으면 위치 추정을 멈추고 보정으로 바꾼다
            st.session?.pointer = nil
            model.hid.sendEmptyReports()
        }
        st.mode = .calibrating
        st.push?.reset()
        st.calibration = RouterCalibration()
        // 아이폰 포인터를 왼쪽 위로
        startPlanLocked(EntryPlan.cornerMoves(dx: -1, dy: -1))
        let gen = st.generation
        lock.unlock()

        if fromMac {
            completeEnter(gen: gen, reason: .menu, placement: p, along: 0, calibrating: true)
        } else {
            model.controlMode = .calibrating
            glow.hide()
            HIDLog.info("보정 시작")
        }
    }

    func cancelCalibration() {
        lock.lock()
        if st.mode == .calibrating {
            st.calibration?.outcome = .cancelled
            beginReturnLocked(.menu)
        }
        lock.unlock()
    }

    private func finishCalibrationLocked(_ cal: RouterCalibration) {
        let c = st.config
        switch Calibration.compute(dx: Double(cal.dx), dy: Double(cal.dy), width: c.phoneWidth, height: c.phoneHeight) {
        case let .success(v): st.calibration?.outcome = .finished(unitsPerPoint: v)
        case let .failure(reason): st.calibration?.outcome = .failed(reason: reason)
        }
        beginReturnLocked(.menu)
    }

    private func scheduleCalibrationMovedLocked() {
        guard !st.movedScheduled else { return }
        st.movedScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.lock.lock()
            self.st.movedScheduled = false
            let cal = self.st.calibration
            self.lock.unlock()
            if let cal { self.calibrationUpdate?(.moved(dx: cal.dx, dy: cal.dy)) }
        }
    }

    // MARK: - 클립보드 보내기

    /// 클립보드의 영문·숫자·기호를 12ms 간격으로 타이핑. 확인 창은 AppModel.requestClipboardSend가 띄운다.
    /// 내용은 로그에 남기지 않는다.
    func typeClipboard() {
        guard model.settings.clipboardTypingAllowed else { return showToast("회사 정책으로 클립보드 보내기가 꺼져 있어요") }
        guard model.isConnected else { return showToast("아이폰이 연결되지 않았어요") }
        let plan = ClipboardTyping.plan(NSPasteboard.general.string(forType: .string) ?? "")
        guard plan.sendable > 0 else { return showToast("보낼 수 있는 글자가 없어요") }

        lock.lock()
        guard st.typing == nil else { lock.unlock(); return }
        st.typing = TypingSession(plan: plan)
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        t.schedule(deadline: .now(), repeating: ClipboardTyping.interval, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.typingTick() }
        st.typingTimer = t
        t.resume()
        lock.unlock()

        HIDLog.info("클립보드 보내기 시작")
        showTypingProgress(remaining: plan.sendable, total: plan.sendable)
    }

    private func typingTick() {
        lock.lock()
        defer { lock.unlock() }
        guard var t = st.typing else { st.typingTimer?.cancel(); st.typingTimer = nil; return }
        let done = t.index >= t.plan.reports.count
        if t.stop || done || !st.config.connected {
            st.typingTimer?.cancel()
            st.typingTimer = nil
            st.typing = nil
            // 글자 중간에 멈췄으면 뗌을 보내고, 아이폰 조작 중이면 지금 눌린 키 상태로 되돌린다
            let restore = st.mode == .phone ? (st.session?.keys.report ?? KeyboardReport()) : KeyboardReport()
            model.hid.send(restore)
            let sent = t.plan.sendable - t.plan.remaining(after: t.index)
            let stopped = !done
            let skipped = t.plan.skipped
            DispatchQueue.main.async {
                HIDLog.info(stopped ? "클립보드 보내기 멈춤" : "클립보드 보내기 끝")
                if stopped {
                    self.showToast("멈췄어요 · \(sent)자까지 보냈어요", systemImage: "stop.circle")
                } else if skipped > 0 {
                    self.showToast("한글 등 일부 글자는 빼고 보냈어요", systemImage: "checkmark")
                } else {
                    self.showToast("보냈어요", systemImage: "checkmark")
                }
            }
            return
        }
        model.hid.send(t.plan.reports[t.index])
        t.index += 1
        st.typing = t
        // 진행 알림은 8리포트(4글자)마다
        if t.index % 8 == 0 {
            let remaining = t.plan.remaining(after: t.index), total = t.plan.sendable
            DispatchQueue.main.async { self.showTypingProgress(remaining: remaining, total: total) }
        }
    }

    private func showTypingProgress(remaining: Int, total: Int) {
        lock.lock()
        let active = st.typing != nil
        lock.unlock()
        guard active else { return }
        let seconds = Int((Double(remaining * 2) * ClipboardTyping.interval).rounded(.up))
        model.toasts.showProgress(title: "아이폰에 입력하는 중", remaining: remaining,
                                  fraction: total > 0 ? Double(total - remaining) / Double(total) : 1,
                                  footnote: "Esc를 누르면 멈춰요 · 약 \(max(seconds, 1))초 남음")
    }

    // MARK: - 그 밖

    private func toggleEdge() {
        model.settings.edgeEnabled.toggle()
        showToast(model.settings.edgeEnabled ? "모서리 전환을 켰어요" : "모서리 전환을 껐어요. 단축키로만 넘어가요",
                  systemImage: model.settings.edgeEnabled ? "rectangle.righthalf.inset.filled" : "keyboard")
    }

    private func showToast(_ text: String, systemImage: String? = nil) {
        if Thread.isMainThread {
            model.showToast(text, systemImage: systemImage)
        } else {
            DispatchQueue.main.async { self.model.showToast(text, systemImage: systemImage) }
        }
    }

    private func requestGlowLocked(progress: Double, along: Double, placement: PlacementInfo) {
        guard st.config.glass else { return }
        st.glowRequest = (progress, along, placement.glow)
        guard !st.glowScheduled else { return }
        st.glowScheduled = true
        DispatchQueue.main.async {
            self.lock.lock()
            let r = self.st.glowRequest
            let mac = self.st.mode == .mac
            self.st.glowRequest = nil
            self.st.glowScheduled = false
            self.lock.unlock()
            if let r, mac { self.glow.push(progress: r.progress, along: r.along, at: r.placement) }
        }
    }

    private func playSound(entering: Bool) {
        guard model.settings.soundEnabled else { return }
        let sound = NSSound(named: entering ? "Tink" : "Pop")
        sound?.volume = 0.3
        sound?.play()
    }

    /// Caps Lock을 막아도 Mac 상태가 바뀔 수 있어서, 돌아올 때 넘어가기 전 상태와 다르면 되돌린다.
    private func restoreCapsLock(_ before: Bool?) {
        guard let before else { return }
        let now = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        guard now != before else { return }
        if CapsLockState.set(before) { HIDLog.info("Caps Lock 상태를 되돌렸어요") }
    }
}

// MARK: - 탭 콜백

private func routerTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputRouter>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

// MARK: - 상태

/// CGEventType에 이름이 없는 종류 (NSEvent.EventType 값)
private enum RawType {
    static let systemDefined: UInt32 = 14
    static let gesture: UInt32 = 29
    /// rotate 18, beginGesture 19, endGesture 20, gesture 29, magnify 30, swipe 31, smartMagnify 32
    static let gestures: [UInt32] = [18, 19, 20, 29, 30, 31, 32]
}

/// 탭 스레드가 읽는 설정 사본 (메인에서 만든다)
private struct RouterConfig {
    var connected = false
    var mayEnter = false
    var edgeEnabled = true
    var glass = true
    var dragLock = true
    var invertScroll = false
    var scrollPointsPerNotch = ScrollConverter.defaultPointsPerNotch
    /// Mac 이동 → 아이폰 HID 단위 배율 (보정 중엔 1:1)
    var pointerScale: Double = 2.0
    var capsLockHangul = true
    var mediaKeysToPhone = false
    var padShortcuts = false
    var hotkeys: [HotkeyAction: KeyCombo] = [:]
    var gestures: [PhoneGesture: GestureSetting] = [:]
    var placement: PlacementInfo?
    var phoneWidth = 393.0
    var phoneHeight = 852.0
    var unitsPerPoint = 2.0
    var mainHeight = 0.0

    func surface(_ p: PlacementInfo) -> PhoneSurface {
        PhoneSurface(width: phoneWidth, height: phoneHeight, unitsPerPoint: unitsPerPoint,
                     macEdge: p.glow.edge, passage: p.glow.passage)
    }
}

private struct PlacementInfo {
    var glow: GlowPlacement
    var threshold: Double
    /// 모니터 가운데 (Quartz 좌표)
    var centerQuartz: CGPoint
}

/// 아이폰 조작(또는 보정) 한 번
private struct PhoneSession {
    var placement: PlacementInfo
    var enterReason: EnterReason
    var glowAlong: Double
    /// 아이폰 안 위치 추정 (보정 중에는 nil)
    var pointer: PhonePointer?
    var held = HeldKeyTracker()
    var keys = KeyboardState()
    /// 아이폰으로 보낸 누름의 Mac 키코드 (돌아온 뒤 뗌을 Mac에 보내지 않으려고)
    var phoneCodes = Set<UInt16>()
    /// 아이폰 마우스 버튼 비트
    var buttons: UInt8 = 0
    /// Mac 버튼 번호 비트
    var macButtons: UInt32 = 0
    /// 넘어갈 때 Mac에서 눌려 있던 버튼 (그 뗌은 Mac에)
    var macButtonsAtEntry: UInt32 = 0
    var scroll = ScrollConverter()
    var remainder = MotionRemainder()
    var gestures = GestureRecognizer()
    var returnGuardUntil: TimeInterval = 0
    var savedCursor: CGPoint?
    var capsLockAtEntry: Bool?

    init(placement: PlacementInfo, enterReason: EnterReason, glowAlong: Double) {
        self.placement = placement
        self.enterReason = enterReason
        self.glowAlong = glowAlong
    }
}

private struct RouterCalibration {
    var ready = false
    var dx = 0
    var dy = 0
    var outcome: CalibrationEvent?
}

private struct TypingSession {
    var plan: ClipboardTyping.Plan
    var index = 0
    var stop = false
}

private struct ReturnInfo {
    var reason: ReturnReason
    var point: CGPoint?
    var placement: PlacementInfo?
    var glowAlong: Double
    var wasCalibrating: Bool
    var calibration: CalibrationEvent?
    var capsLockAtEntry: Bool?
}

private struct TapState {
    var mode: ControlMode = .mac
    /// 움직임 끊김 진단: Mac 마우스 이벤트 간격
    var moveEvents = GapMeter()
    var generation = 0
    var config = RouterConfig()

    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var tapRunLoop: CFRunLoop?
    var starting = false
    var stopRequested = false

    // Mac 조작 중
    var push: EdgePush?
    var macButtons: UInt32 = 0
    /// 뗌(과 누른 채 반복)을 Mac에 보내지 않을 키 — 단축키, 아이폰에서 누른 채 돌아온 키
    var swallowKeyUp = Set<UInt16>()
    var swallowMouseUp: UInt32 = 0
    var glowRequest: (progress: Double, along: Double, placement: GlowPlacement)?
    var glowScheduled = false

    // 아이폰 조작 · 보정 중
    var session: PhoneSession?
    var plan: [HIDMove] = []
    var planIndex = 0
    var planTimer: DispatchSourceTimer?
    var calibration: RouterCalibration?
    var movedScheduled = false

    // 클립보드 보내기
    var typing: TypingSession?
    var typingTimer: DispatchSourceTimer?
}

// MARK: - 로그 이름

private extension EnterReason {
    var logLabel: String {
        switch self {
        case .edge: return "모서리"
        case .hotkey: return "단축키"
        case .menu: return "메뉴"
        }
    }
}

private extension ReturnReason {
    var logLabel: String {
        switch self {
        case .edge: return "모서리"
        case .hotkey: return "단축키"
        case .menu: return "메뉴"
        case .secureInput: return "비밀번호 입력"
        case .tapDisabled: return "입력 감시 꺼짐"
        case .disconnected: return "연결 끊김"
        case .permissionLost: return "권한 꺼짐"
        case .screenLocked: return "화면 잠금"
        case .screensChanged: return "모니터 구성 변경"
        case .transportStalled: return "전송 지연"
        case .sleep: return "잠자기"
        }
    }
}

// MARK: - 비공개·저수준 API (없으면 건너뜀)

/// 백그라운드 앱도 커서를 숨길 수 있게 하는 비공개 API (CGSSetConnectionProperty "SetsCursorInBackground").
/// App Store 배포 불가 항목 (설계 문서 › 위험 요소). 함수를 못 찾으면 아무것도 하지 않는다.
private enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private static var done = false

    static func enableOnce() {
        guard !done else { return }
        done = true
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let c = dlsym(handle, "_CGSDefaultConnection"), let s = dlsym(handle, "CGSSetConnectionProperty") else {
            HIDLog.warn("백그라운드 커서 숨김을 쓸 수 없어요 (함수 없음)")
            return
        }
        let connection = unsafeBitCast(c, to: DefaultConnection.self)()
        let r = unsafeBitCast(s, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        if r != 0 { HIDLog.warn("백그라운드 커서 숨김 설정 실패 (\(r))") }
    }
}

/// Mac Caps Lock 상태 바꾸기 (IOHIDSetModifierLockState). 없거나 실패하면 false.
private enum CapsLockState {
    private typealias SetLock = @convention(c) (io_connect_t, Int32, Bool) -> kern_return_t

    static func set(_ on: Bool) -> Bool {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDSetModifierLockState") else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        // kIOHIDParamConnectType = 1
        guard IOServiceOpen(service, mach_task_self_, 1, &connect) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connect) }
        // kIOHIDCapsLockState = 1
        return unsafeBitCast(sym, to: SetLock.self)(connect, 1, on) == KERN_SUCCESS
    }
}
