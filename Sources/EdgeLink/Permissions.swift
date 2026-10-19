import AppKit
import ApplicationServices
import CoreBluetooth
import Foundation

/// 필수 권한 3가지: 블루투스, 손쉬운 사용, 입력 모니터링. 1초마다 확인한다.
final class Permissions: NSObject, ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case bluetooth, accessibility, inputMonitoring
        var id: String { rawValue }

        var title: String {
            switch self {
            case .bluetooth: return "블루투스"
            case .accessibility: return "손쉬운 사용"
            case .inputMonitoring: return "입력 모니터링"
            }
        }

        /// 화면 문구 (설계 문서 › macOS 권한 설계)
        var why: String {
            switch self {
            case .bluetooth: return "Mac이 아이폰에 키보드·마우스로 보이게 해요"
            case .accessibility: return "아이폰 조작 중엔 입력이 Mac에 가지 않도록 막아요"
            case .inputMonitoring: return "키보드 입력을 읽어서 아이폰으로 보내요"
            }
        }

        var glyph: String {
            switch self {
            case .bluetooth: return "B"
            case .accessibility: return "A"
            case .inputMonitoring: return "K"
            }
        }

        var settingsURL: URL {
            let anchor: String
            switch self {
            case .bluetooth: anchor = "Privacy_Bluetooth"
            case .accessibility: anchor = "Privacy_Accessibility"
            case .inputMonitoring: anchor = "Privacy_ListenEvent"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    enum BluetoothState: Equatable { case notDetermined, denied, granted }

    @Published private(set) var bluetooth: BluetoothState = .notDetermined
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    /// 시스템 설정을 연 권한과 연 시각 (60초 지나도 안 켜지면 회사 정책 안내)
    @Published private(set) var waiting: (kind: Kind, since: Date)?
    @Published private(set) var waitingTooLong = false

    /// 허용돼 있다가 꺼진 권한. 앱은 Mac 조작으로 돌아오고 경고를 띄운다.
    @Published private(set) var revoked: Kind?

    private var timer: Timer?
    private var central: CBCentralManager?
    private var everGranted: Set<Kind> = []
    private var ticks = 0
    /// 한 번 요청한 권한. 두 번째부터는 시스템 설정을 연다.
    private var requested: Set<Kind> = []

    override init() {
        super.init()
        refresh()
        // 시스템 설정을 열어둔 동안은 0.25초, 평소엔 1초마다 확인
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            if self.waiting != nil || self.ticks % 4 == 0 { self.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    var allGranted: Bool { bluetooth == .granted && accessibility && inputMonitoring }

    func isGranted(_ kind: Kind) -> Bool {
        switch kind {
        case .bluetooth: return bluetooth == .granted
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        }
    }

    /// 아직 허용 안 된 첫 권한 (순서: 블루투스 → 손쉬운 사용 → 입력 모니터링)
    var firstMissing: Kind? { Kind.allCases.first { !isGranted($0) } }

    @objc private func appBecameActive() { refresh() }

    func refresh() {
        let bt: BluetoothState
        switch CBManager.authorization {
        case .allowedAlways: bt = .granted
        case .notDetermined: bt = .notDetermined
        default: bt = .denied
        }
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        if bt != bluetooth { bluetooth = bt }
        if ax != accessibility { accessibility = ax }
        if im != inputMonitoring { inputMonitoring = im }

        for kind in Kind.allCases {
            if isGranted(kind) {
                everGranted.insert(kind)
                if revoked == kind { revoked = nil }
            } else if everGranted.contains(kind), revoked == nil {
                revoked = kind
            }
        }

        if let w = waiting {
            if isGranted(w.kind) {
                waiting = nil
                waitingTooLong = false
            } else if !waitingTooLong, Date().timeIntervalSince(w.since) >= 60 {
                waitingTooLong = true
            }
        }
    }

    /// 권한 요청. 블루투스는 시스템 창이 앱 안에서 뜨고, 나머지는 시스템 설정을 연다.
    func request(_ kind: Kind) {
        switch kind {
        case .bluetooth:
            if bluetooth == .notDetermined {
                // CBCentralManager를 만들면 시스템 권한 창이 뜬다
                central = CBCentralManager(delegate: self, queue: nil)
            } else {
                open(kind)
            }
        case .accessibility:
            if requested.contains(kind) { return open(kind) }
            requested.insert(kind)
            waiting = (kind, Date())
            waitingTooLong = false
            // 시스템 창이 뜬다 (목록에 EdgeLink가 추가됨)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            if requested.contains(kind) { return open(kind) }
            requested.insert(kind)
            waiting = (kind, Date())
            waitingTooLong = false
            if !CGRequestListenEventAccess() { open(kind) }
        }
    }

    func open(_ kind: Kind) {
        waiting = (kind, Date())
        waitingTooLong = false
        NSWorkspace.shared.open(kind.settingsURL)
    }

    /// 관리자에게 보낼 내용 (캔버스 2-4 회사 정책)
    static var adminRequestText: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.edgelink.EdgeLink"
        return """
        EdgeLink 사용을 위해 아래 권한 허용을 요청드려요.

        앱 이름: EdgeLink
        번들 ID: \(bundleID)
        필요한 권한:
        - 블루투스: Mac이 아이폰에 키보드·마우스로 보이게 해요
        - 손쉬운 사용: 아이폰 조작 중엔 입력이 Mac에 가지 않도록 막아요
        - 입력 모니터링: 키보드 입력을 읽어서 아이폰으로 보내요

        입력 내용은 저장하거나 인터넷으로 보내지 않아요.
        """
    }
}

extension Permissions: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refresh()
    }
}
