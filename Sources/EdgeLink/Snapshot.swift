import AppKit
import SwiftUI

/// 개발용: 화면을 창 없이 PNG로 그린다. 화면 녹화 권한이 필요 없다.
///   EDGELINK_SNAPSHOT=<폴더> build/EdgeLink.app/Contents/MacOS/EdgeLink
///   EDGELINK_SNAPSHOT_APPEARANCE=dark 를 같이 주면 다크 모드
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["EDGELINK_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 캡처용 설정 저장소: 지금 설정을 복사하되 실제 기기 이름은 예시 이름으로 바꾼다 (캡처에 개인정보가 찍히지 않게)
    static let defaults: UserDefaults = {
        let suite = "com.edgelink.snapshot"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        for (k, v) in UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:] {
            d.set(v, forKey: k)
        }
        if d.string(forKey: "lastDeviceName") != nil { d.set(sampleDevice.name, forKey: "lastDeviceName") }
        if d.string(forKey: "lastDeviceAddress") != nil { d.set(sampleDevice.address, forKey: "lastDeviceAddress") }
        return d
    }()

    /// 캡처에 보이는 페어링 기기 (실제 페어링 목록 대신)
    static let sampleDevice = DeviceDirectory.Item(address: "00-11-22-33-44-55", name: "지민의 iPhone 16 Pro", paired: true, kind: .phone)

    static func run(model: AppModel) {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dark = ProcessInfo.processInfo.environment["EDGELINK_SNAPSHOT_APPEARANCE"] == "dark"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let suffix = dark ? "-dark" : ""

        for step in OnboardingStep.allCases {
            model.onboardingPage = step
            let view = OnboardingView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.permissions)
                .environmentObject(model.devices)
            render(view.frame(height: 560), size: NSSize(width: 720, height: 560), appearance: appearance,
                   to: dir.appendingPathComponent(String(format: "onboarding-%d%@.png", step.rawValue, suffix)))
        }
        // 담당별 캡처 (설정 창, 팝오버 상태별, 확인 창 등): 각 파일의 extension Snapshot에서 한 줄씩 추가
        // 예: renderSettings(model: model, dir: dir, appearance: appearance, suffix: suffix)
        renderSettings(model: model, dir: dir, appearance: appearance, suffix: suffix)
        renderPopoverAndDialogs(model: model, dir: dir, appearance: appearance, suffix: suffix)
        exit(0)
    }

    /// 담당별 캡처 함수도 이걸 쓴다 (size가 nil이면 내용에 맞춤)
    static func render<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance?, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let fit = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fit), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: fit)
        host.layoutSubtreeIfNeeded()
        // 애니메이션·onAppear가 한 번 돌게 런루프를 잠깐 돌린다
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
