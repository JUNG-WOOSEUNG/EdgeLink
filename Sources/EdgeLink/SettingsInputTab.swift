import EdgeLinkCore
import AppKit
import SwiftUI

// 설정 › 입력 (캔버스 3-1 입력 탭, 4-3 단축키 기록 중·겹침)

struct InputTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    /// 캡처용: 기록 중·겹침 상태를 처음부터 보여준다
    var previewPhases: [HotkeyAction: HotkeyRecorderRow.Phase] = [:]
    @State private var recording: HotkeyAction?
    @State private var showBlockedList = false
    /// Mac이 먼저 가져가는 트랙패드 제스처 (창을 열 때 한 번 읽는다)
    @State private var macGestures: Set<PhoneGesture> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            shortcuts
            phoneToggles
            gestures
        }
        .onAppear { macGestures = TrackpadGestures.usedByMac() }
    }

    // MARK: 단축키 8개

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "단축키")
                Spacer()
                if settings.hotkeys != Hotkey.defaults {
                    Button("모두 기본값으로") { settings.hotkeys = Hotkey.defaults }
                        .buttonStyle(TextLinkStyle(color: .brandText))
                        .font(Typo.font(12, .semibold))
                }
            }
            SettingsGroup {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element.id) { i, action in
                    if i > 0 { RowDivider() }
                    HotkeyRecorderRow(action: action, title: action.settingsLabel, active: $recording,
                                      initialPhase: previewPhases[action] ?? .idle)
                }
            }
            Text("버튼을 누르고 새 조합을 입력하면 바뀌어요. 다른 동작이나 macOS 단축키와 겹치면 저장하지 않아요. 오른쪽 클릭하면 기본값으로 돌아가요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 아이폰으로 보낼 때

    private var phoneToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 막을 수 없는 단축키 안내는 제목 위 (캔버스 3-1)
            blockedHelp
            SectionLabel(text: "아이폰으로 보낼 때")
            SettingsGroup {
                ToggleRow(title: "스크롤 방향 반전", hint: "아이폰에서만 반대로 스크롤해요", isOn: $settings.invertScroll)
                RowDivider()
                ToggleRow(title: "Caps Lock으로 한/영 전환", hint: "Caps Lock을 누르면 아이폰에 ⌃Space를 보내요", isOn: $settings.capsLockHangul)
                RowDivider()
                ToggleRow(title: "드래그 중엔 넘어가지 않기", hint: "파일이나 창을 끌다 실수로 넘어가는 걸 막아요", isOn: $settings.dragLock)
                RowDivider()
                ToggleRow(title: "미디어 키를 아이폰으로", hint: "아이폰 조작 중엔 볼륨·재생 키를 아이폰에 보내요. 밝기 키는 Mac에서 동작해요", isOn: $settings.mediaKeysToPhone)
            }
            SettingsCard {
                RowText(title: "포인터 속도", hint: "가운데면 Mac에서 움직인 만큼 아이폰에서도 움직여요")
                HStack(spacing: 12) {
                    Text("느리게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    Slider(value: $settings.pointerSpeed, in: PointerScale.speedRange)
                        .tint(Color.brand)
                        .accessibilityLabel("포인터 속도")
                        .accessibilityValue(String(format: "%.1f배", settings.pointerSpeed))
                    Text("빠르게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 2)
                RowDivider()
                RowText(title: "스크롤 속도", hint: "두 손가락으로 스크롤할 때 아이폰에서 움직이는 양이에요")
                HStack(spacing: 12) {
                    Text("느리게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    Slider(value: $settings.scrollSpeed, in: 0...1)
                        .tint(Color.brand)
                        .accessibilityLabel("스크롤 속도")
                        .accessibilityValue("\(Int((settings.scrollSpeed * 100).rounded()))퍼센트")
                    Text("빠르게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 2)
            }
        }
    }

    /// 막을 수 없는 시스템 단축키 도움말
    private var blockedHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("⌘Tab, Mission Control처럼 macOS가 먼저 처리하는 단축키는 아이폰 조작 중에도 Mac에서 동작할 수 있어요.")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(showBlockedList ? "접기" : "목록 보기") {
                    withAnimation(.easeOut(duration: 0.15)) { showBlockedList.toggle() }
                }
                .buttonStyle(TextLinkStyle(color: .brandText))
                .font(Typo.font(12, .semibold))
                .fixedSize()
                .accessibilityLabel(showBlockedList ? "막을 수 없는 단축키 목록 접기" : "막을 수 없는 단축키 목록 보기")
            }
            if showBlockedList {
                GrayCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        blocked("⌘Tab", "앱 전환 (Mac 앱이 바뀌어요)")
                        blocked("⌃↑ · ⌃↓ · ⌃← · ⌃→", "Mission Control, 공간 이동")
                        blocked("⌘Space", "Spotlight")
                        blocked("⇧⌘3 · ⇧⌘4 · ⇧⌘5", "화면 캡처")
                        blocked("⌃⌘Q", "화면 잠금 (잠기면 Mac으로 돌아와요)")
                        blocked("Fn · Globe", "받아쓰기·이모지 (아이폰에 보내지 않아요)")
                    }
                }
            }
        }
    }

    private func blocked(_ keys: String, _ what: String) -> some View {
        HStack(spacing: 12) {
            Text(keys).font(Typo.font(12, .semibold)).frame(width: 150, alignment: .leading)
            Text(what).font(Typo.secondary).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 제스처를 아이폰 동작으로

    private var gestures: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: "제스처를 아이폰 동작으로")
                Spacer()
                if settings.gestureButtonsRegistered {
                    Badge(text: "아이폰 등록함", fg: .successText, bg: Color.success.opacity(0.14))
                } else {
                    Badge(text: "아이폰 등록 전", fg: .warningText, bg: .warningBg)
                }
                Button(settings.gestureButtonsRegistered ? "다시 등록" : "아이폰 버튼 등록") {
                    model.settingsWindow.showGestureSetup()
                }
                .buttonStyle(PillButtonStyle(kind: settings.gestureButtonsRegistered ? .secondary : .primary, height: 30))
            }
            SettingsGroup {
                ForEach(Array(PhoneGesture.allCases.filter { $0 != .lockOnly }.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { RowDivider() }
                    gestureRow(g)
                }
                if settings.profile.model.isPad {
                    RowDivider()
                    ToggleRow(title: "아이패드는 키보드 단축키로", hint: "버튼 대신 ⌘H(홈), ⌘Tab(앱 전환)을 보내요. 아이패드에선 더 확실해요",
                              isOn: $settings.padUsesShortcuts)
                }
            }
            Text("제스처는 마우스 추가 버튼으로 바꿔 보내요. 아이폰 AssistiveTouch에 버튼을 한 번 등록해야 동작해요. 앱 사이 좌우 넘기기와 뒤로 가기는 지원하지 않아요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gestureRow(_ g: PhoneGesture) -> some View {
        let setting = settings.gestureMap[g] ?? GestureSetting.defaults[g]!
        let hotkey = settings.hotkeys[g.hotkeyAction] ?? Hotkey.defaults[g.hotkeyAction]!
        var hint = setting.hotkeyEnabled ? "단축키 \(hotkey.display)" : "단축키 꺼짐"
        // 시스템 설정 › 트랙패드에서 같은 제스처가 켜져 있는 줄에만 덧붙인다
        if macGestures.contains(g) { hint += " · Mac이 먼저 쓸 수 있어요" }
        return ToggleRow(title: g.label, hint: hint, isOn: Binding(get: { setting.gestureEnabled }, set: { on in
            var s = setting
            s.gestureEnabled = on
            settings.gestureMap[g] = s
        })) {
            Menu {
                ForEach(4...8, id: \.self) { n in
                    Button("버튼 \(n)\(n == setting.button ? " (지금)" : "")") {
                        var s = setting
                        s.button = n
                        settings.gestureMap[g] = s
                    }
                }
            } label: {
                Text("버튼 \(setting.button) → \(g.phoneAction)")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(Typo.font(12, .semibold))
            .foregroundStyle(Color.brandStrong)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.brandTint))
            .accessibilityLabel("\(g.label) 보낼 버튼: 버튼 \(setting.button), \(g.phoneAction)")
            .help("보낼 버튼 번호를 바꿔요")
        }
    }
}

/// 작은 상태 알약
struct Badge: View {
    var text: String
    var fg: Color
    var bg: Color
    var body: some View {
        Text(text)
            .font(Typo.font(11.5, .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }
}

/// macOS가 먼저 쓰는 트랙패드 제스처 (시스템 설정 › 트랙패드 › 추가 제스처)
enum TrackpadGestures {
    static func usedByMac() -> Set<PhoneGesture> {
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        func on(_ key: String) -> Bool {
            domains.contains { UserDefaults(suiteName: $0)?.integer(forKey: key) ?? 0 != 0 }
        }
        var out: Set<PhoneGesture> = []
        // 세 손가락 위·아래: Mission Control, 앱 윈도우
        if on("TrackpadThreeFingerVertSwipeGesture") { out.formUnion([.threeFingerUp, .threeFingerDown]) }
        // 네 손가락 위·아래
        if on("TrackpadFourFingerVertSwipeGesture") { out.insert(.fourFingerDown) }
        // 네 손가락 모으기: Launchpad
        if on("TrackpadFourFingerPinchGesture") { out.insert(.fourFingerPinch) }
        return out
    }
}
