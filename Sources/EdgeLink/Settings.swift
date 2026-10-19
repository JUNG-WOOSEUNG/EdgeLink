import EdgeLinkCore
import Foundation

/// 설정 저장 (UserDefaults). 입력 내용은 저장하지 않는다. 키 이름은 설계 문서 › 저장 데이터 표.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    enum Key {
        static let lastDeviceAddress = "lastDeviceAddress"
        static let lastDeviceName = "lastDeviceName"
        static let onlyDefaultDevice = "onlyDefaultDevice"
        static let phoneLayout = "phoneLayout"
        static let profiles = "profiles"
        static let sensitivity = "sensitivity"
        static let unitsPerPoint = "unitsPerPoint"
        static let edgeEnabled = "edgeEnabled"
        static let autoReconnect = "autoReconnect"
        static let disconnectOnSleep = "disconnectOnSleep"
        static let onboardingStep = "onboardingStep"
        static let onboardingDone = "onboardingDone"
        static let remoteActive = "remoteActive"
        static let hotkeys = "hotkeys"
        static let gestureMap = "gestureMap"
        static let gestureButtonsRegistered = "gestureButtonsRegistered"
        static let glassEnabled = "glassEnabled"
        static let soundEnabled = "soundEnabled"
        static let invertScroll = "invertScroll"
        static let capsLockHangul = "capsLockHangul"
        static let dragLock = "dragLock"
        static let mediaKeysToPhone = "mediaKeysToPhone"
        static let clipboardConfirmSkip = "clipboardConfirmSkip"
        static let showDeviceNameInMenuBar = "showDeviceNameInMenuBar"
        static let autoUpdateCheck = "autoUpdateCheck"
        static let padUsesShortcuts = "padUsesShortcuts"
        // 관리 설정 (회사 배포판)
        static let clipboardTypingAllowed = "clipboardTypingAllowed"
        static let autoUpdateAllowed = "autoUpdateAllowed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.onlyDefaultDevice: true,
            Key.sensitivity: 0.5,
            Key.unitsPerPoint: 2.0,
            Key.edgeEnabled: true,
            Key.autoReconnect: true,
            Key.disconnectOnSleep: true,
            Key.onboardingStep: 0,
            Key.onboardingDone: false,
            Key.glassEnabled: true,
            Key.soundEnabled: false,
            Key.invertScroll: false,
            Key.capsLockHangul: true,
            Key.dragLock: true,
            Key.mediaKeysToPhone: false,
            Key.clipboardConfirmSkip: false,
            Key.showDeviceNameInMenuBar: false,
            Key.autoUpdateCheck: true,
            Key.padUsesShortcuts: true,
            Key.clipboardTypingAllowed: true,
            Key.autoUpdateAllowed: true,
        ])
        lastDeviceAddress = defaults.string(forKey: Key.lastDeviceAddress)
        lastDeviceName = defaults.string(forKey: Key.lastDeviceName)
        onboardingStep = defaults.integer(forKey: Key.onboardingStep)
        onboardingDone = defaults.bool(forKey: Key.onboardingDone)
        phoneLayout = Self.decode(PhoneLayout.self, defaults.data(forKey: Key.phoneLayout))
        profile = Self.decode([String: DeviceProfile].self, defaults.data(forKey: Key.profiles))?.values.first ?? DeviceProfile()
        hotkeys = Self.decode([HotkeyAction: Hotkey].self, defaults.data(forKey: Key.hotkeys)).map { Hotkey.defaults.merging($0) { $1 } } ?? Hotkey.defaults
        gestureMap = Self.decode([PhoneGesture: GestureSetting].self, defaults.data(forKey: Key.gestureMap)).map { GestureSetting.defaults.merging($0) { $1 } } ?? GestureSetting.defaults
        gestureButtonsRegistered = defaults.bool(forKey: Key.gestureButtonsRegistered)
        onlyDefaultDevice = defaults.bool(forKey: Key.onlyDefaultDevice)
        sensitivityValue = defaults.double(forKey: Key.sensitivity)
        unitsPerPointValue = defaults.double(forKey: Key.unitsPerPoint)
        edgeEnabled = defaults.bool(forKey: Key.edgeEnabled)
        autoReconnectValue = defaults.bool(forKey: Key.autoReconnect)
        disconnectOnSleep = defaults.bool(forKey: Key.disconnectOnSleep)
        remoteActive = defaults.bool(forKey: Key.remoteActive)
        glassEnabled = defaults.bool(forKey: Key.glassEnabled)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        invertScroll = defaults.bool(forKey: Key.invertScroll)
        capsLockHangul = defaults.bool(forKey: Key.capsLockHangul)
        dragLock = defaults.bool(forKey: Key.dragLock)
        mediaKeysToPhone = defaults.bool(forKey: Key.mediaKeysToPhone)
        clipboardConfirmSkip = defaults.bool(forKey: Key.clipboardConfirmSkip)
        showDeviceNameInMenuBar = defaults.bool(forKey: Key.showDeviceNameInMenuBar)
        autoUpdateCheck = defaults.bool(forKey: Key.autoUpdateCheck)
        padUsesShortcuts = defaults.bool(forKey: Key.padUsesShortcuts)
    }

    @Published var lastDeviceAddress: String? { didSet { defaults.set(lastDeviceAddress, forKey: Key.lastDeviceAddress) } }
    @Published var lastDeviceName: String? { didSet { defaults.set(lastDeviceName, forKey: Key.lastDeviceName) } }
    /// 마지막으로 끝낸 단계 번호 (0 = 아직 시작 안 함)
    @Published var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: Key.onboardingStep) } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboardingDone) } }
    @Published var phoneLayout: PhoneLayout? { didSet { defaults.set(Self.encode(phoneLayout), forKey: Key.phoneLayout) } }
    @Published var profile: DeviceProfile { didSet { saveProfile() } }

    /// 동작별 단축키 (기본 3개 + 제스처 5개)
    @Published var hotkeys: [HotkeyAction: Hotkey] { didSet { defaults.set(Self.encode(hotkeys), forKey: Key.hotkeys) } }
    /// 제스처별 켜기, 버튼 번호
    @Published var gestureMap: [PhoneGesture: GestureSetting] { didSet { defaults.set(Self.encode(gestureMap), forKey: Key.gestureMap) } }
    @Published var gestureButtonsRegistered: Bool { didSet { defaults.set(gestureButtonsRegistered, forKey: Key.gestureButtonsRegistered) } }
    @Published var onlyDefaultDevice: Bool { didSet { defaults.set(onlyDefaultDevice, forKey: Key.onlyDefaultDevice) } }
    /// 전환 감도 0~1 (기준 = 60 + 감도 × 200pt)
    @Published var sensitivityValue: Double { didSet { defaults.set(sensitivityValue, forKey: Key.sensitivity) } }
    /// 아이폰 1pt당 HID 이동량 (보정값, 기본 2.0, 범위 0.6~4.0)
    @Published var unitsPerPointValue: Double { didSet { defaults.set(unitsPerPointValue, forKey: Key.unitsPerPoint) } }
    /// 모서리 전환
    @Published var edgeEnabled: Bool { didSet { defaults.set(edgeEnabled, forKey: Key.edgeEnabled) } }
    @Published var autoReconnectValue: Bool { didSet { defaults.set(autoReconnectValue, forKey: Key.autoReconnect) } }
    @Published var disconnectOnSleep: Bool { didSet { defaults.set(disconnectOnSleep, forKey: Key.disconnectOnSleep) } }
    /// 아이폰 조작 중 여부 (충돌 후 복구 확인용)
    @Published var remoteActive: Bool { didSet { defaults.set(remoteActive, forKey: Key.remoteActive) } }
    /// 모서리 유리 효과
    @Published var glassEnabled: Bool { didSet { defaults.set(glassEnabled, forKey: Key.glassEnabled) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var invertScroll: Bool { didSet { defaults.set(invertScroll, forKey: Key.invertScroll) } }
    /// Caps Lock으로 한/영 (켜면 아이폰에 ⌃Space)
    @Published var capsLockHangul: Bool { didSet { defaults.set(capsLockHangul, forKey: Key.capsLockHangul) } }
    /// 드래그 중 전환 막기
    @Published var dragLock: Bool { didSet { defaults.set(dragLock, forKey: Key.dragLock) } }
    @Published var mediaKeysToPhone: Bool { didSet { defaults.set(mediaKeysToPhone, forKey: Key.mediaKeysToPhone) } }
    @Published var clipboardConfirmSkip: Bool { didSet { defaults.set(clipboardConfirmSkip, forKey: Key.clipboardConfirmSkip) } }
    @Published var showDeviceNameInMenuBar: Bool { didSet { defaults.set(showDeviceNameInMenuBar, forKey: Key.showDeviceNameInMenuBar) } }
    @Published var autoUpdateCheck: Bool { didSet { defaults.set(autoUpdateCheck, forKey: Key.autoUpdateCheck) } }
    /// 아이패드면 제스처를 버튼 대신 ⌘H, ⌘Tab으로
    @Published var padUsesShortcuts: Bool { didSet { defaults.set(padUsesShortcuts, forKey: Key.padUsesShortcuts) } }

    /// 관리 설정 (회사 배포판에서 MDM으로 끔). 앱에서는 읽기만 한다.
    var clipboardTypingAllowed: Bool { defaults.bool(forKey: Key.clipboardTypingAllowed) }
    var autoUpdateAllowed: Bool { defaults.bool(forKey: Key.autoUpdateAllowed) }

    var autoReconnect: Bool { autoReconnectValue }
    var unitsPerPoint: Double { unitsPerPointValue }
    var sensitivity: Double { sensitivityValue }

    /// 페어링 초기화: 기기 정보와 온보딩 진행을 지운다 (설정값은 유지)
    func resetPairing() {
        lastDeviceAddress = nil
        lastDeviceName = nil
        phoneLayout = nil
        gestureButtonsRegistered = false
        resetOnboarding()
    }

    private func saveProfile() {
        let key = lastDeviceAddress ?? "default"
        defaults.set(Self.encode([key: profile]), forKey: Key.profiles)
    }

    /// 온보딩 다시 보기 · 페어링 초기화용
    func resetOnboarding() {
        onboardingStep = 0
        onboardingDone = false
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }
}

/// 아이폰을 놓은 자리: 모니터 UUID, 모서리, 모서리 시작점에서의 거리.
struct PhoneLayout: Codable, Equatable {
    var screenID: String
    var edge: ScreenEdge
    var offset: Double
}

struct DeviceProfile: Codable, Equatable {
    enum Model: String, Codable, CaseIterable, Identifiable {
        case iPhone, iPhoneMini, iPhoneMax, iPad, iPadPro13
        var id: String { rawValue }
        var label: String {
            switch self {
            case .iPhone: return "iPhone (일반 크기)"
            case .iPhoneMini: return "iPhone mini"
            case .iPhoneMax: return "iPhone Plus·Pro Max"
            case .iPad: return "iPad"
            case .iPadPro13: return "iPad Pro 13"
            }
        }
        var isPad: Bool { self == .iPad || self == .iPadPro13 }

        /// 세로 기준 화면 크기(pt). 돌아오는 위치 계산과 커서 가운데 맞추기에 쓴다.
        var screenSize: (width: Double, height: Double) {
            switch self {
            case .iPhone: return (393, 852)
            case .iPhoneMini: return (375, 812)
            case .iPhoneMax: return (430, 932)
            case .iPad: return (820, 1180)
            case .iPadPro13: return (1032, 1376)
            }
        }

        /// 블루투스 이름으로 화면 크기를 고른다 ("지민의 iPhone 16 Pro" → iPhone). 모르면 nil.
        static func infer(from name: String?) -> Model? {
            guard let n = name?.lowercased() else { return nil }
            if n.contains("ipad") { return n.contains("13") || n.contains("12.9") ? .iPadPro13 : .iPad }
            guard n.contains("iphone") else { return nil }
            if n.contains("pro max") || n.contains("plus") || n.contains("max") { return .iPhoneMax }
            if n.contains("mini") { return .iPhoneMini }
            return .iPhone
        }
    }

    var model: Model = .iPhone
    var landscape = false
    /// 사용자가 직접 고른 크기면 이름으로 덮어쓰지 않는다
    var manual = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(Model.self, forKey: .model) ?? .iPhone
        landscape = try c.decodeIfPresent(Bool.self, forKey: .landscape) ?? false
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
    }
}

// MARK: - 단축키

/// 단축키로 하는 동작 (설계 문서 › 단축키 기본값, 제스처를 아이폰 동작으로)
enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleRemote, sendClipboard, toggleEdge
    case appSwitcher, home, notificationCenter, controlCenter, lockScreen
    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggleRemote: return "Mac ↔ 아이폰 전환"
        case .sendClipboard: return "클립보드 보내기"
        case .toggleEdge: return "모서리 전환 켜기/끄기"
        case .appSwitcher: return "앱 전환기"
        case .home: return "홈"
        case .notificationCenter: return "알림 센터"
        case .controlCenter: return "제어 센터"
        case .lockScreen: return "잠금 화면"
        }
    }

    /// 제스처를 대신하는 단축키인지
    var gesture: PhoneGesture? {
        switch self {
        case .appSwitcher: return .threeFingerUp
        case .home: return .fourFingerPinch
        case .notificationCenter: return .threeFingerDown
        case .controlCenter: return .fourFingerDown
        case .lockScreen: return .lockOnly
        default: return nil
        }
    }
}

/// 키코드(kVK_*) + 수정키. 수정키는 CGEventFlags의 ⌃⌥⇧⌘ 비트만 쓴다.
struct Hotkey: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64

    static let control: UInt64 = 0x40000   // CGEventFlags.maskControl
    static let option: UInt64 = 0x80000    // .maskAlternate
    static let shift: UInt64 = 0x20000     // .maskShift
    static let command: UInt64 = 0x100000  // .maskCommand
    static let all: UInt64 = control | option | shift | command
    static let ctrlOptCmd: UInt64 = control | option | command

    /// ⌃⌥⌘Space처럼 보이는 글자
    var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            0x31: "Space", 0x24: "↩", 0x30: "⇥", 0x33: "⌫", 0x35: "Esc",
            0x7E: "↑", 0x7D: "↓", 0x7B: "←", 0x7C: "→",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I",
            0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
            0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        ]
        return names[code] ?? String(format: "키 %d", code)
    }

    /// 기본값은 모두 ⌃⌥⌘. ⌃⌥만 쓰면 VoiceOver 조작키, ⌃⌥Space는 입력 소스 전환과 겹친다.
    static let defaults: [HotkeyAction: Hotkey] = [
        .toggleRemote: Hotkey(keyCode: 0x31, modifiers: ctrlOptCmd),
        .sendClipboard: Hotkey(keyCode: 0x09, modifiers: ctrlOptCmd),
        .toggleEdge: Hotkey(keyCode: 0x0E, modifiers: ctrlOptCmd),
        .appSwitcher: Hotkey(keyCode: 0x7E, modifiers: ctrlOptCmd),
        .home: Hotkey(keyCode: 0x04, modifiers: ctrlOptCmd),
        .notificationCenter: Hotkey(keyCode: 0x7D, modifiers: ctrlOptCmd),
        .controlCenter: Hotkey(keyCode: 0x08, modifiers: ctrlOptCmd),
        .lockScreen: Hotkey(keyCode: 0x25, modifiers: ctrlOptCmd),
    ]
}

// MARK: - 제스처

/// 트랙패드 제스처 → 아이폰 AssistiveTouch 추가 버튼(4~8)
enum PhoneGesture: String, Codable, CaseIterable, Identifiable {
    case threeFingerUp, fourFingerPinch, threeFingerDown, fourFingerDown, lockOnly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .threeFingerUp: return "세 손가락 위로 쓸기"
        case .fourFingerPinch: return "네 손가락 모으기"
        case .threeFingerDown: return "세 손가락 아래로 쓸기"
        case .fourFingerDown: return "네 손가락 아래로 쓸기"
        case .lockOnly: return "없음 (단축키만)"
        }
    }

    /// 아이폰에서 지정할 동작 (기본 추천)
    var phoneAction: String {
        switch self {
        case .threeFingerUp: return "앱 전환기"
        case .fourFingerPinch: return "홈"
        case .threeFingerDown: return "알림 센터"
        case .fourFingerDown: return "제어 센터"
        case .lockOnly: return "잠금 화면"
        }
    }

    var hotkeyAction: HotkeyAction {
        switch self {
        case .threeFingerUp: return .appSwitcher
        case .fourFingerPinch: return .home
        case .threeFingerDown: return .notificationCenter
        case .fourFingerDown: return .controlCenter
        case .lockOnly: return .lockScreen
        }
    }
}

struct GestureSetting: Codable, Equatable {
    /// 제스처를 아이폰 동작으로 바꿔 보낼지
    var gestureEnabled: Bool
    /// 대체 단축키를 쓸지
    var hotkeyEnabled: Bool
    /// 보내는 마우스 추가 버튼 (4~8)
    var button: Int

    static let defaults: [PhoneGesture: GestureSetting] = [
        .threeFingerUp: GestureSetting(gestureEnabled: true, hotkeyEnabled: true, button: 4),
        .fourFingerPinch: GestureSetting(gestureEnabled: true, hotkeyEnabled: true, button: 5),
        .threeFingerDown: GestureSetting(gestureEnabled: true, hotkeyEnabled: true, button: 6),
        .fourFingerDown: GestureSetting(gestureEnabled: true, hotkeyEnabled: true, button: 7),
        .lockOnly: GestureSetting(gestureEnabled: false, hotkeyEnabled: true, button: 8),
    ]
}
