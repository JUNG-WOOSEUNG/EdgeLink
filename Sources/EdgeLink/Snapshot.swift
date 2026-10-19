import AppKit
import SwiftUI

/// 개발용: 화면을 창 없이 PNG로 그린다. 화면 녹화 권한이 필요 없다.
///   EDGELINK_SNAPSHOT=<폴더> build/EdgeLink.app/Contents/MacOS/EdgeLink
///   EDGELINK_SNAPSHOT_APPEARANCE=dark 를 같이 주면 다크 모드
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["EDGELINK_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

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
            render(view, size: NSSize(width: 720, height: 560), appearance: appearance,
                   to: dir.appendingPathComponent(String(format: "onboarding-%d%@.png", step.rawValue, suffix)))
        }
        let popover = PopoverView()
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.permissions)
        render(popover, size: nil, appearance: appearance, to: dir.appendingPathComponent("popover\(suffix).png"))
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance?, to url: URL) {
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
