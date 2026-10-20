import AppKit
import SwiftUI

/// 개발용 캡처: 설정 창 5개 탭, 빈 상태, 단축키 기록 중·겹침, 아이폰 버튼 등록 도우미.
/// 설정값(UserDefaults)은 바꾸지 않는다. 연결 상태와 기기 목록만 흉내 낸다.
extension Snapshot {
    static func renderSettings(model: AppModel, dir: URL, appearance: NSAppearance?, suffix: String) {
        let size = NSSize(width: 860, height: 640)
        let tall = NSSize(width: 860, height: 1500)
        let sampleDevices = [
            DeviceDirectory.Item(address: "00-11-22-33-44-55", name: "iPhone 15 Pro", paired: true, kind: .phone),
            DeviceDirectory.Item(address: "00-11-22-33-44-66", name: "iPad Air", paired: true, kind: .pad),
        ]
        let sampleDefault = "00-11-22-33-44-55"

        func settingsView(_ tab: SettingsTab, content: AnyView? = nil) -> some View {
            let state = SettingsWindowState()
            state.tab = tab
            return SettingsView(state: state, override: content)
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.permissions)
                .environmentObject(model.devices)
        }
        func save<V: View>(_ view: V, _ name: String, _ s: NSSize = size) {
            render(view, size: s, appearance: appearance, to: dir.appendingPathComponent("\(name)\(suffix).png"))
        }

        model.debugSetConnection(.connected(name: "iPhone 15 Pro"))
        for tab in SettingsTab.allCases {
            let content: AnyView? = tab == .connection
                ? AnyView(ConnectionTab(preview: (sampleDevices, sampleDefault))) : nil
            save(settingsView(tab, content: content), "settings-\(tab.rawValue)")
            save(settingsView(tab, content: content), "settings-\(tab.rawValue)-full", tall)
        }

        // 빈 상태 · 기록 중 · 겹침
        save(settingsView(.layout, content: AnyView(LayoutTab(previewPlacements: []))), "settings-layout-empty")
        save(settingsView(.connection, content: AnyView(ConnectionTab(preview: ([], nil)))), "settings-connection-empty")
        let attempt = Hotkey(keyCode: 0x09, modifiers: Hotkey.ctrlOptCmd)
        save(settingsView(.input, content: AnyView(InputTab(previewPhases: [
            .toggleRemote: .recording(held: 0),
            .toggleEdge: .rejected(attempt: attempt, message: "‘클립보드 보내기’에서 이미 쓰는 조합이에요"),
        ]))), "settings-input-recording")

        // 아이폰 버튼 등록 도우미
        let gSize = NSSize(width: 720, height: 560)
        func gesture(_ p: (index: Int, sent: Bool, testing: Bool)) -> some View {
            GestureSetupView(onClose: {}, preview: p)
                .environmentObject(model)
                .environmentObject(model.settings)
        }
        save(gesture((0, false, false)), "gesture-setup", gSize)
        save(gesture((1, true, false)), "gesture-setup-sent", gSize)
        save(gesture((5, false, false)), "gesture-setup-done", gSize)
        save(gesture((5, false, true)), "gesture-setup-test", gSize)

        // 연결 안 됨: 보정 도우미·버튼 보내기가 흐려지고 이유가 보인다
        model.debugSetConnection(.idle)
        save(settingsView(.layout), "settings-layout-offline-full", tall)
        save(gesture((0, false, false)), "gesture-setup-offline", gSize)
    }
}
