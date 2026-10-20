import AppKit
import EdgeLinkCore
import SwiftUI

/// 트랙패드 제스처 설정 (720×560, 캔버스 1-9 · 설계 문서 › 아이폰 버튼 등록 도우미)
/// 버튼 4~8을 차례로 보내고, 아이폰에서 동작을 고르면 "등록했어요, 다음"으로 다음 버튼으로 넘어간다.
struct GestureSetupView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    var onClose: () -> Void
    /// 캡처용 시작 상태
    var preview: (index: Int, sent: Bool, testing: Bool)?

    @State private var index = 0
    @State private var sent = false
    @State private var testing = false
    @State private var hostName = "이 Mac"

    private struct Step {
        let gesture: PhoneGesture
        var action: String { gesture.phoneAction }
    }

    private let steps = PhoneGesture.allCases.map(Step.init)
    private var allDone: Bool { index >= steps.count }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44) // 신호등 버튼 자리
            HStack(alignment: .top, spacing: 32) {
                phoneColumn
                if testing { testPane } else { registerPane }
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)
            .padding(.bottom, 24) // 바닥 줄까지 최소 24
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        // 높이를 고정하지 않고 창을 채운다
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgWindow)
        .foregroundStyle(Color.textPrimary)
        .ignoresSafeArea()
        .onAppear {
            if let p = preview { index = p.index; sent = p.sent; testing = p.testing }
            if let name = BluetoothHID.hostInfo()?.name, !name.isEmpty { hostName = name }
        }
    }

    // MARK: 왼쪽 아이폰 화면

    private var phoneColumn: some View {
        VStack(spacing: 10) {
            // 윤곽은 PhoneArt가 Color.deviceOutline으로 그린다 (다크에서도 바탕과 구분)
            PhoneArt(width: 150, height: 300, bezel: 7) { phoneScreen }
            Text("아이폰 화면").font(Typo.caption).foregroundStyle(Color.textSecondary)
        }
        .frame(width: 168)
        .accessibilityElement()
        .accessibilityLabel(phoneAccessibility)
    }

    private var phoneAccessibility: String {
        if allDone || testing { return "아이폰 화면: 추가 버튼 사용자화" }
        return sent ? "아이폰 화면: 버튼 \(current.gesture.buttonNumber(settings))의 동작 고르기" : "아이폰 화면: 버튼을 누르세요"
    }

    private var current: Step { steps[min(index, steps.count - 1)] }

    private var phoneScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("‹ \(hostName)").font(.system(size: 9)).foregroundStyle(Color(hex: 0x0077B6)).lineLimit(1)
            Text(!allDone && sent && !testing ? "버튼 \(current.gesture.buttonNumber(settings))" : "추가 버튼 사용자화")
                .font(.system(size: 12, weight: .heavy))
            if allDone || testing {
                VStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        phoneListRow("버튼 \(steps[i].gesture.buttonNumber(settings))", steps[i].action, bold: false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            } else if sent {
                VStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        phoneListRow(steps[i].action, steps[i].action == current.action ? "✓" : "", bold: steps[i].action == current.action)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            } else {
                VStack(spacing: 6) {
                    Text("버튼을 누르세요").font(.system(size: 10, weight: .bold))
                    Text("사용자화할 버튼을 포인터 기기에서 누르세요")
                        .font(.system(size: 8)).foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 8).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                .padding(.top, 24)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(hex: 0x1A1A1A))
        .padding(EdgeInsets(top: 24, leading: 10, bottom: 10, trailing: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0xF2F2F7))
    }

    private func phoneListRow(_ name: String, _ mark: String, bold: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(name)
                Spacer()
                Text(mark)
            }
            .font(.system(size: 9, weight: bold ? .bold : .regular))
            .foregroundStyle(bold ? Color(hex: 0x0077B6) : Color(hex: 0x1A1A1A))
            .padding(.horizontal, 8).padding(.vertical, 6)
            Rectangle().fill(Color(hex: 0xF2F2F7)).frame(height: 1)
        }
    }

    // MARK: 오른쪽 등록 단계

    private var registerPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("아이폰에 버튼을 등록해요").font(Typo.onboardingTitle)
                    .accessibilityAddTraits(.isHeader)
                // 긴 메뉴 경로를 한 문장에 넣지 않고 단계로 나눈다
                VStack(alignment: .leading, spacing: 4) {
                    guideLine(1) {
                        // Mac 이름 앞에서 줄을 바꿔 이름이 둘로 갈리지 않게 한다
                        Text("아이폰에서 ")
                            + Text("설정 › 손쉬운 사용 › 터치 › AssistiveTouch › 기기 ›\n\(hostName.nonBreaking)")
                                .fontWeight(.semibold).foregroundColor(.textPrimary)
                            + Text("(이\u{00A0}Mac의\u{00A0}이름)")
                            + Text(" › 추가\u{00A0}버튼\u{00A0}사용자화").fontWeight(.semibold).foregroundColor(.textPrimary)
                            + Text("를 여세요")
                    }
                    guideLine(2) { Text("‘버튼을 누르세요’가 뜨면 아래 표에서 보내기를 누르세요") }
                    // 버튼 번호는 아이폰이 붙이는 이름이라 4부터 시작해요
                    guideLine(3) { Text("아이폰 화면에 ‘버튼 4’처럼 번호가 뜨면 표대로 동작을 고르세요. 다른 동작을 골라도 괜찮아요.") }
                }
                .font(Typo.secondary)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                // 연결이 안 됐을 때 이유는 줄마다 쓰지 않고 표 위에 한 번만
                if !model.isConnected && !allDone {
                    DisabledReason(text: "아이폰을 연결하면 버튼을 보낼 수 있어요")
                }
                VStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        if i > 0 { RowDivider() }
                        stepRow(i)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.settingsCard))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 안내 한 단계: 번호 + 문장
    private func guideLine<C: View>(_ n: Int, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Typo.font(12, .bold)).foregroundStyle(Color.brandText)
                .frame(width: 10, alignment: .leading)
            content().fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func stepRow(_ i: Int) -> some View {
        let step = steps[i]
        let n = step.gesture.buttonNumber(settings)
        let done = i < index, isCurrent = i == index
        let hotkey = settings.hotkeys[step.gesture.hotkeyAction] ?? Hotkey.defaults[step.gesture.hotkeyAction]!
        let hint = step.gesture == .lockOnly ? "단축키 \(hotkey.display)" : "\(step.gesture.label) · \(hotkey.display)"
        return VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
            stepDot(n, done: done, current: isCurrent)
            VStack(alignment: .leading, spacing: 2) {
                Text("버튼 \(n) → \(step.action)").font(Typo.bodyBold)
                Text(hint).font(Typo.caption).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "등록함" : isCurrent ? "지금 할 차례" : "")
            if isCurrent && !sent {
                VStack(alignment: .trailing, spacing: 4) {
                    Button("버튼 \(n) 보내기") {
                        model.router.sendButton(n)
                        sent = true
                    }
                    .buttonStyle(DimmablePillStyle(height: 32))
                    .disabled(!model.isConnected)
                }
                .fixedSize()
            } else if isCurrent && sent {
                // 다음으로 넘어가는 주요 행동. 다시 보내기는 아래 안내 줄에 둔다.
                Button("등록했어요, 다음") { confirm() }
                    .buttonStyle(PillButtonStyle(height: 32))
                    .accessibilityHint("다음 버튼으로 넘어가요")
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        // 아이폰이 못 알아챌 때: 아이폰 조작 중에 단축키로 보내면 확실히 알아챔 (실기기 확인)
        if isCurrent && sent {
            fallbackHint(hotkey, button: n)
        }
        }
    }

    private func fallbackHint(_ hotkey: Hotkey, button n: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb").font(.system(size: 11)).foregroundStyle(Color.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("아이폰에 번호가 뜨지 않았나요?")
                    Button("다시 보내기") { model.router.sendButton(n) }
                        .buttonStyle(TextLinkStyle(color: .brandText))
                        .font(Typo.font(11.5, .semibold))
                        .disabled(!model.isConnected)
                }
                Text("그래도 안 되면 \(toggleKey)로 넘어가서 \(hotkey.display)를 눌러 보세요.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Typo.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(.leading, 52).padding(.trailing, 14).padding(.bottom, 8)
    }

    private var toggleKey: String {
        (settings.hotkeys[.toggleRemote] ?? Hotkey.defaults[.toggleRemote]!).display
    }

    /// 번호 원. 끝낸 단계는 진한 초록(#28A745) 위 흰 ✓ 12pt bold — 다크에서도 연초록으로 바꾸지 않는다 (대비).
    private func stepDot(_ n: Int, done: Bool, current: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(Color(hex: 0x28A745))
            } else if current {
                Circle().fill(Color.brandFill)
            } else {
                Circle().strokeBorder(Color.textDecor, lineWidth: 1.5)
            }
            // ✓는 SUIT에 글리프가 없어 가는 대체 글꼴로 그려지므로 SF Symbol을 쓴다
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Text("\(n)")
                    .font(Typo.font(12, .heavy))
                    .foregroundStyle(current ? Color.white : .textSecondary)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func confirm() {
        sent = false
        index += 1
        if allDone, preview == nil { settings.gestureButtonsRegistered = true }
    }

    // MARK: 시험해보기

    /// 시험 표에는 제스처가 있는 것만. 잠금 화면(단축키만)은 따로 한 줄로 쓴다.
    private var gestureSteps: [Step] { steps.filter { $0.gesture != .lockOnly } }

    private func hotkeyFor(_ g: PhoneGesture) -> Hotkey {
        settings.hotkeys[g.hotkeyAction] ?? Hotkey.defaults[g.hotkeyAction]!
    }

    private var testPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("제스처를 해 봐요").font(Typo.onboardingTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("아이폰 조작 중에 트랙패드로 아래 제스처를 해 보세요. 아이폰에서 그 동작이 열리면 성공이에요. 단축키로도 해 볼 수 있어요.")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(gestureSteps.enumerated()), id: \.offset) { i, step in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.gesture.label).font(Typo.bodyBold)
                            Text("버튼 \(step.gesture.buttonNumber(settings)) → \(step.action)")
                                .font(Typo.caption).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 키 캡 최소 너비 60, 글자는 가운데
                        Text(hotkeyFor(step.gesture).display)
                            .font(Typo.bodyBold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(minWidth: 60)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.segmentBg))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.settingsCard))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text("잠금 화면은 단축키 \(hotkeyFor(.lockOnly).display)로만 열어요.")
                Text("Mac에서 Mission Control이나 Launchpad가 대신 열리면 시스템 설정 › 트랙패드 › 추가 제스처에서 그 제스처를 끄세요.")
                Text("동작하지 않으면 아이폰에서 AssistiveTouch가 켜져 있는지, 등록한 버튼 번호가 맞는지 확인하세요.")
            }
            .font(Typo.caption).foregroundStyle(Color.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 바닥

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.line).frame(height: 1)
            HStack(spacing: 12) {
                if testing {
                    Button("다시 등록") {
                        testing = false
                        index = 0
                        sent = false
                    }
                    .buttonStyle(TextLinkStyle())
                } else {
                    Button("나중에 하기", action: onClose).buttonStyle(TextLinkStyle())
                }
                Spacer()
                if testing {
                    Button("완료", action: onClose)
                        .buttonStyle(PillButtonStyle(height: 40))
                        .keyboardShortcut(.defaultAction)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(min(index, steps.count)) / \(steps.count) 등록")
                            .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        // 흐린 버튼 옆에 이유 한 줄
                        if !allDone { DisabledReason(text: "모두 등록하면 시험할 수 있어요") }
                    }
                    Button("시험해 보기") { testing = true }
                        .buttonStyle(DimmablePillStyle(height: 40))
                        .disabled(!allDone)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 72)
        }
    }
}

extension PhoneGesture {
    /// 설정에 저장한 버튼 번호 (기본 4~8)
    func buttonNumber(_ settings: AppSettings) -> Int {
        settings.gestureMap[self]?.button ?? GestureSetting.defaults[self]?.button ?? 4
    }
}
