import AppKit
import SwiftUI

/// 개발용 캡처: 팝오버 상태별, 확인 창 전부. 실제 설정(UserDefaults)은 바꾸지 않는다.
extension Snapshot {
    static func renderPopoverAndDialogs(model: AppModel, dir: URL, appearance: NSAppearance?, suffix: String) {
        func save<V: View>(_ name: String, _ view: V) {
            let v = view
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.permissions)
            render(v, size: nil, appearance: appearance, to: dir.appendingPathComponent("\(name)\(suffix).png"))
        }

        // 캡처 중에는 실제 기기에 다시 연결하지 않는다 (AppModel이 블루투스를 먼저 켜 둔 경우)
        model.hid.autoReconnect = false
        model.hid.cancelReconnect()
        model.hid.disconnect()

        // 팝오버
        save("popover-setup", PopoverView(preview: PopoverPreview(state: .setup)))
        model.debugSetConnection(.idle)
        save("popover-disconnected", PopoverView(preview: PopoverPreview(state: .disconnected)))
        save("popover-no-device", PopoverView(preview: PopoverPreview(state: .disconnected, noDevice: true)))
        model.debugSetConnection(.failed(message: "인터럽트 채널 열기 실패 (0xe00002bc)"))
        save("popover-failed", PopoverView(preview: PopoverPreview(state: .disconnected)))
        model.debugSetConnection(.connecting)
        save("popover-connecting", PopoverView(preview: PopoverPreview(state: .disconnected)))
        save("popover-problem-permission", PopoverView(preview: PopoverPreview(state: .problem(.permission(.accessibility)))))
        save("popover-problem-bluetooth", PopoverView(preview: PopoverPreview(state: .problem(.bluetoothOff))))
        save("popover-problem-policy", PopoverView(preview: PopoverPreview(state: .problem(.policy(.inputMonitoring)))))

        model.debugSetConnection(.connected(name: "지민의 iPhone 16 Pro"))
        model.controlMode = .mac
        save("popover-connected-mac", PopoverView(preview: PopoverPreview(state: .connected)))
        save("popover-connected-menu", PopoverView(preview: PopoverPreview(state: .connected, menuOpen: true)))
        model.controlMode = .phone
        save("popover-connected-phone", PopoverView(preview: PopoverPreview(state: .connected)))
        model.controlMode = .mac

        // 확인 창
        let h = DialogHandle()
        save("dialog-connection-request", ConnectionRequestView(name: "지민의 iPhone", address: "a4:83:5c:12:34:56", handle: h))
        save("dialog-clipboard", ClipboardConfirmView(sendable: 38, skipped: 6, handle: h,
                                                       previewText: "meeting-room-3F · pw: Abc!2345 회의실 3층"))
        save("dialog-shortcut-conflict", ShortcutConflictView(action: .toggleRemote,
                                                              hotkey: Hotkey(keyCode: 0x31, modifiers: Hotkey.control | Hotkey.option),
                                                              conflictsWith: "입력 소스 전환", handle: h))
        save("dialog-reset-pairing", ResetPairingView(handle: h))
        save("dialog-connection-log", ConnectionLogView(handle: h, fixedLines: [
            "10:20:01.120 [INFO] SDP 레코드 등록됨",
            "10:20:01.480 [INFO] 지민의 iPhone 16 Pro에 연결 중…",
            "10:20:02.002 [ERROR] 연결 실패: PSM 0x11, 0xe00002bc",
            "10:20:17.010 [INFO] 15초 뒤 다시 시도",
            "10:20:17.300 [INFO] 지민의 iPhone 16 Pro에 연결 중…",
            "10:20:18.044 [WARN] 쓰기 지연 62ms",
            "10:20:18.210 [INFO] 채널 2개 열림 · 연결됨 (a4:83:5c:12:34:56)",
            "10:21:40.501 [INFO] → 아이폰 조작 (LG UltraFine 오른쪽)",
            "10:22:05.877 [INFO] ← Mac 조작",
        ]))
        let phases: [(String, CalibrationSession.Phase)] = [
            ("intro", .intro(note: nil)),
            ("measuring", .measuring(dx: 742, dy: 1580)),
            ("done", .done(old: 2.0, new: 2.12)),
            ("failed", .failed(title: "움직인 양이 너무 적어요", reason: "아이폰 포인터를 오른쪽 아래 끝까지 옮기기 전에 클릭한 것 같아요.")),
        ]
        for (name, phase) in phases {
            save("dialog-calibration-\(name)", CalibrationView(session: CalibrationSession(model: model, phase: phase), handle: h))
        }
        model.debugSetConnection(.idle)
        save("dialog-calibration-offline", CalibrationView(session: CalibrationSession(model: model), handle: h))
    }
}
