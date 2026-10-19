import AppKit
import SwiftUI

/// 단축키를 기록하는 중인지. 기록하는 동안은 ⌘, 같은 앱 단축키를 받지 않는다.
/// InputRouter도 이 값이 true면 전환 단축키를 처리하지 않아야 한다 (합칠 때 연결).
enum HotkeyRecorderState {
    static var isRecording = false
}

// MARK: - 겹침 확인

/// macOS 시스템 단축키와 VoiceOver 조작키 겹침 (설계 문서 › 단축키 기본값)
enum SystemShortcuts {
    struct Entry {
        let name: String
        let hotkey: Hotkey
    }

    /// com.apple.symbolichotkeys 번호와 macOS 기본값. 사용자가 바꿨거나 껐으면 그 값을 따른다.
    private static let symbolic: [(id: Int, name: String, keyCode: UInt16, modifiers: UInt64)] = [
        (60, "입력 소스 전환", 0x31, Hotkey.control),                       // ⌃Space 이전 입력 소스
        (61, "입력 소스 전환", 0x31, Hotkey.control | Hotkey.option),       // ⌃⌥Space 다음 입력 소스
        (32, "Mission Control", 0x7E, Hotkey.control),                      // ⌃↑
        (33, "앱 윈도우", 0x7D, Hotkey.control),                             // ⌃↓
        (79, "왼쪽 공간으로 이동", 0x7B, Hotkey.control),                    // ⌃←
        (81, "오른쪽 공간으로 이동", 0x7C, Hotkey.control),                  // ⌃→
        (64, "Spotlight", 0x31, Hotkey.command),                            // ⌘Space
        (65, "Finder 검색", 0x31, Hotkey.option | Hotkey.command),          // ⌥⌘Space
        (28, "화면 캡처", 0x14, Hotkey.shift | Hotkey.command),             // ⇧⌘3
        (30, "화면 캡처", 0x15, Hotkey.shift | Hotkey.command),             // ⇧⌘4
        (184, "화면 캡처", 0x17, Hotkey.shift | Hotkey.command),            // ⇧⌘5
    ]

    /// 바꿀 수 없는 시스템 단축키
    private static let fixed: [Entry] = [
        Entry(name: "앱 전환", hotkey: Hotkey(keyCode: 0x30, modifiers: Hotkey.command)),               // ⌘Tab
        Entry(name: "화면 잠금", hotkey: Hotkey(keyCode: 0x0C, modifiers: Hotkey.control | Hotkey.command)), // ⌃⌘Q
    ]

    /// 지금 켜져 있는 시스템 단축키
    static func current() -> [Entry] {
        let dict = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        var out = fixed
        for s in symbolic {
            var hotkey = Hotkey(keyCode: s.keyCode, modifiers: s.modifiers)
            if let entry = dict[String(s.id)] as? [String: Any] {
                if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { continue }
                if let value = entry["value"] as? [String: Any], let p = value["parameters"] as? [NSNumber], p.count >= 3 {
                    let code = p[1].intValue
                    if code == 65535 || code < 0 { continue } // 키가 지정되지 않음
                    hotkey = Hotkey(keyCode: UInt16(code), modifiers: p[2].uint64Value & Hotkey.all)
                }
            }
            out.append(Entry(name: s.name, hotkey: hotkey))
        }
        return out
    }

    /// 겹치는 시스템 단축키 이름. 없으면 nil.
    static func conflict(_ hotkey: Hotkey) -> String? {
        let mods = hotkey.modifiers & Hotkey.all
        if NSWorkspace.shared.isVoiceOverEnabled, mods == Hotkey.control | Hotkey.option {
            return "VoiceOver 조작키"
        }
        return current().first { $0.hotkey.keyCode == hotkey.keyCode && $0.hotkey.modifiers & Hotkey.all == mods }?.name
    }
}

// MARK: - 기록 버튼

/// 단축키 버튼. 누르면 기록을 시작하고, 수정키와 함께 키를 누르면 저장한다. Esc는 취소.
struct HotkeyRecorderRow: View {
    enum Phase: Equatable {
        case idle
        case recording(held: UInt64)
        /// 저장하지 않음 (다른 동작과 겹침, 수정키 없음, 시스템 단축키와 겹침)
        case rejected(attempt: Hotkey, message: String)
    }

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let action: HotkeyAction
    var title: String
    /// 지금 기록 중인 동작 (한 번에 하나만)
    @Binding var active: HotkeyAction?
    /// 캡처용: 처음 보여줄 상태
    var initialPhase: Phase = .idle

    @State private var phase: Phase = .idle
    @State private var monitor: Any?
    @State private var noModifierHint = false

    private var hotkey: Hotkey { settings.hotkeys[action] ?? Hotkey.defaults[action]! }
    /// 제스처 대체 단축키를 껐는지
    private var hotkeyOff: Bool {
        guard let g = action.gesture else { return false }
        return settings.gestureMap[g]?.hotkeyEnabled == false
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 12) {
                Text(title).font(Typo.font(14, .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: toggleRecording) {
                    Text(buttonText)
                        .font(Typo.font(13, .semibold))
                        .foregroundStyle(foreground)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 130)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(background))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: isIdle ? 1 : 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) 단축키")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("누르고 새 조합을 입력하세요. Esc는 취소예요.")
                .contextMenu {
                    if action.gesture != nil {
                        Button(hotkeyOff ? "단축키 켜기" : "단축키 끄기") { setHotkeyEnabled(hotkeyOff) }
                    }
                    Button("기본값으로") {
                        settings.hotkeys[action] = Hotkey.defaults[action]
                        phase = .idle
                    }
                    .disabled(hotkey == Hotkey.defaults[action])
                }
            }
            switch phase {
            case .recording:
                Text("⌃ ⌥ ⇧ ⌘ 중 하나 이상과 함께 누르세요 · Esc 취소")
                    .font(Typo.secondary)
                    .foregroundStyle(noModifierHint ? Color.dangerText : .textSecondary)
            case let .rejected(_, message):
                Text(message).font(Typo.secondary).foregroundStyle(Color.dangerText)
            case .idle:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .onAppear { if phase == .idle, initialPhase != .idle { phase = initialPhase } }
        .onChange(of: active) { a in if a != action, case .recording = phase { stop(keep: .idle) } }
        .onDisappear { stop(keep: .idle) }
    }

    private var isIdle: Bool { if case .idle = phase { return true } else { return false } }

    private var buttonText: String {
        switch phase {
        case .idle: return hotkeyOff ? "꺼짐" : hotkey.display
        case let .recording(held): return held == 0 ? "키를 누르세요…" : Hotkey.modifierSymbols(held) + "…"
        case let .rejected(attempt, _): return attempt.display
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .idle: return hotkeyOff ? "꺼짐" : hotkey.spoken
        case .recording: return "기록 중"
        case let .rejected(attempt, message): return "\(attempt.spoken), \(message)"
        }
    }

    private var foreground: Color {
        switch phase {
        case .idle: return hotkeyOff ? .textSecondary : .textPrimary
        case .recording: return .brandStrong
        case .rejected: return .dangerText
        }
    }

    private var background: Color {
        switch phase {
        case .idle: return Color(light: 0xF5F5F7, dark: 0x333336)
        case .recording: return .brandTint
        case .rejected: return .errorBg
        }
    }

    private var border: Color {
        switch phase {
        case .idle: return .control
        case .recording: return .brand
        case .rejected: return .danger
        }
    }

    private func setHotkeyEnabled(_ on: Bool) {
        guard let g = action.gesture, var s = settings.gestureMap[g] else { return }
        s.hotkeyEnabled = on
        settings.gestureMap[g] = s
    }

    private func toggleRecording() {
        if case .recording = phase { return stop(keep: .idle) }
        start()
    }

    private func start() {
        active = action
        noModifierHint = false
        phase = .recording(held: 0)
        HotkeyRecorderState.isRecording = true
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil // 기록 중엔 다른 곳으로 보내지 않는다
        }
    }

    private func stop(keep next: Phase) {
        removeMonitor()
        HotkeyRecorderState.isRecording = false
        if active == action { active = nil }
        phase = next
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let mods = UInt64(event.modifierFlags.intersection([.control, .option, .shift, .command]).rawValue) & Hotkey.all
        if event.type == .flagsChanged {
            phase = .recording(held: mods)
            return
        }
        if event.isARepeat { return }
        if event.keyCode == 0x35, mods == 0 { return stop(keep: .idle) } // Esc
        guard mods != 0 else {
            noModifierHint = true
            NSSound.beep()
            return
        }
        let candidate = Hotkey(keyCode: event.keyCode, modifiers: mods)
        if candidate == hotkey { return stop(keep: .idle) }
        if let other = HotkeyAction.allCases.first(where: { $0 != action && settings.hotkeys[$0] == candidate }) {
            return stop(keep: .rejected(attempt: candidate, message: "‘\(other.settingsLabel)’에서 이미 쓰는 조합이에요"))
        }
        if let system = SystemShortcuts.conflict(candidate) {
            // 저장하지 않고 확인 창에서 고르게 한다 ("그래도 쓰기"를 누르면 확인 창이 저장)
            stop(keep: .rejected(attempt: candidate, message: "‘\(system)’과 겹쳐서 아직 저장하지 않았어요"))
            model.present(.shortcutConflict(action: action, hotkey: candidate, conflictsWith: system))
            return
        }
        settings.hotkeys[action] = candidate
        if action.gesture != nil { setHotkeyEnabled(true) }
        stop(keep: .idle)
    }
}

extension HotkeyAction {
    /// 설정 › 입력 목록의 이름 (제스처 대체 단축키는 "아이폰 홈"처럼)
    var settingsLabel: String { gesture == nil ? label : "아이폰 \(label)" }
}

extension Hotkey {
    static func modifierSymbols(_ m: UInt64) -> String {
        var s = ""
        if m & control != 0 { s += "⌃" }
        if m & option != 0 { s += "⌥" }
        if m & shift != 0 { s += "⇧" }
        if m & command != 0 { s += "⌘" }
        return s
    }

    /// VoiceOver가 읽는 이름 ("Control Option Command Space")
    var spoken: String {
        var parts: [String] = []
        if modifiers & Self.control != 0 { parts.append("Control") }
        if modifiers & Self.option != 0 { parts.append("Option") }
        if modifiers & Self.shift != 0 { parts.append("Shift") }
        if modifiers & Self.command != 0 { parts.append("Command") }
        let arrows: [UInt16: String] = [0x7E: "위쪽 화살표", 0x7D: "아래쪽 화살표", 0x7B: "왼쪽 화살표", 0x7C: "오른쪽 화살표",
                                        0x24: "Return", 0x30: "Tab", 0x33: "Delete", 0x35: "Escape"]
        parts.append(arrows[keyCode] ?? Self.keyName(keyCode))
        return parts.joined(separator: " ")
    }
}
