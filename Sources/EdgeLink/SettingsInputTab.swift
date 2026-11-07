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
    /// "모두 기본값으로" 직전 단축키 (되돌리기용)
    @State private var undoHotkeys: [HotkeyAction: Hotkey]?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            shortcuts
            phoneToggles
        }
    }

    // MARK: 단축키

    private var shortcuts: some View {
        SettingsSection(title: "단축키",
                        info: "버튼을 누르고 새 조합을 입력하면 바뀌어요. 다른 동작이나 macOS 단축키와 겹치면 저장하지 않아요. 오른쪽 클릭하면 기본값으로 되돌릴 수 있어요.") {
            HStack(spacing: Space.s) {
                if let undo = undoHotkeys, settings.hotkeys == Hotkey.defaults {
                    // 확인 없이 3개를 한 번에 되돌리므로, 바로 되살릴 수 있게 한다
                    Text("모두 기본값으로 바꿨어요").font(Typo.caption).foregroundStyle(Color.textSecondary)
                    Button("되돌리기") {
                        settings.hotkeys = undo
                        undoHotkeys = nil
                    }
                    .buttonStyle(TextLinkStyle(color: .brandText))
                } else if settings.hotkeys != Hotkey.defaults {
                    Button("모두 기본값으로") {
                        undoHotkeys = settings.hotkeys
                        settings.hotkeys = Hotkey.defaults
                    }
                    .buttonStyle(TextLinkStyle(color: .brandText))
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: Space.s) {
                SettingsGroup {
                    ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element.id) { i, action in
                        if i > 0 { RowDivider() }
                        HotkeyRecorderRow(action: action, title: action.label, active: $recording,
                                          initialPhase: previewPhases[action] ?? .idle)
                    }
                }
                blockedHelp
            }
        }
    }

    // MARK: 아이폰으로 보낼 때

    private var phoneToggles: some View {
        SettingsSection(title: "아이폰으로 보낼 때") {
            VStack(alignment: .leading, spacing: Space.l) {
                SettingsGroup {
                    ToggleRow(title: "스크롤 방향 반전", hint: "아이폰에서만 반대로 스크롤해요", isOn: $settings.invertScroll)
                    RowDivider()
                    ToggleRow(title: "Caps Lock으로 한/영 전환", hint: "아이폰 입력 언어를 바꿔요", isOn: $settings.capsLockHangul)
                    RowDivider()
                    ToggleRow(title: "드래그 중엔 넘어가지 않기", hint: "파일이나 창을 끌다 실수로 넘어가는 걸 막아요", isOn: $settings.dragLock)
                    RowDivider()
                    ToggleRow(title: "미디어 키를 아이폰으로", hint: "볼륨·재생 키를 아이폰에 보내요",
                              info: "아이폰을 조작하는 동안만 보내요. 밝기 키는 늘 Mac에서 동작해요.", isOn: $settings.mediaKeysToPhone)
                }
                SettingsCard {
                    RowText(title: "포인터 속도", hint: "가운데면 Mac에서 움직인 만큼 아이폰에서도 움직여요")
                    HStack(spacing: Space.m) {
                        Text("느리게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        Slider(value: $settings.pointerSpeed, in: PointerScale.speedRange)
                            .tint(Color.brand)
                            .accessibilityLabel("포인터 속도")
                            .accessibilityValue(String(format: "%.1f배", settings.pointerSpeed))
                        Text("빠르게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    }
                    RowDivider().padding(.vertical, Space.xs)
                    RowText(title: "스크롤 속도", hint: "두 손가락으로 스크롤할 때 움직이는 양이에요")
                    HStack(spacing: Space.m) {
                        Text("느리게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        Slider(value: $settings.scrollSpeed, in: 0...1)
                            .tint(Color.brand)
                            .accessibilityLabel("스크롤 속도")
                            .accessibilityValue("\(Int((settings.scrollSpeed * 100).rounded()))퍼센트")
                        Text("빠르게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    /// 막을 수 없는 시스템 단축키 도움말
    private var blockedHelp: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                SettingsFootnote(text: "⌘Tab처럼 macOS가 먼저 처리하는 단축키는 아이폰 조작 중에도 Mac에서 동작해요")
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
                GrayCard(padding: Space.m) {
                    VStack(alignment: .leading, spacing: Space.s) {
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
        HStack(spacing: Space.m) {
            Text(keys).font(Typo.font(12, .semibold)).frame(width: 150, alignment: .leading)
            Text(what).font(Typo.secondary).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
