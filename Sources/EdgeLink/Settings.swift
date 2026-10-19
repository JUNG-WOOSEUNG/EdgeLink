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
        ])
        lastDeviceAddress = defaults.string(forKey: Key.lastDeviceAddress)
        lastDeviceName = defaults.string(forKey: Key.lastDeviceName)
        onboardingStep = defaults.integer(forKey: Key.onboardingStep)
        onboardingDone = defaults.bool(forKey: Key.onboardingDone)
        phoneLayout = Self.decode(PhoneLayout.self, defaults.data(forKey: Key.phoneLayout))
        profile = Self.decode([String: DeviceProfile].self, defaults.data(forKey: Key.profiles))?.values.first ?? DeviceProfile()
    }

    @Published var lastDeviceAddress: String? { didSet { defaults.set(lastDeviceAddress, forKey: Key.lastDeviceAddress) } }
    @Published var lastDeviceName: String? { didSet { defaults.set(lastDeviceName, forKey: Key.lastDeviceName) } }
    /// 마지막으로 끝낸 단계 번호 (0 = 아직 시작 안 함)
    @Published var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: Key.onboardingStep) } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboardingDone) } }
    @Published var phoneLayout: PhoneLayout? { didSet { defaults.set(Self.encode(phoneLayout), forKey: Key.phoneLayout) } }
    @Published var profile: DeviceProfile { didSet { saveProfile() } }

    var autoReconnect: Bool { defaults.bool(forKey: Key.autoReconnect) }
    var sensitivity: Double { defaults.double(forKey: Key.sensitivity) }

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
            case .iPhone: return "iPhone"
            case .iPhoneMini: return "iPhone mini"
            case .iPhoneMax: return "iPhone Plus·Pro Max"
            case .iPad: return "iPad"
            case .iPadPro13: return "iPad Pro 13"
            }
        }
        var isPad: Bool { self == .iPad || self == .iPadPro13 }

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
