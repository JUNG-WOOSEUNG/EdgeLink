import AppKit
import EdgeLinkCore
import SwiftUI

// 확인 창 내용 (캔버스 4-1 연결 요청·클립보드·단축키 겹침, 4-4 페어링 초기화)

/// 확인 창 공통 틀: 너비 420, 안쪽 여백 24
struct DialogFrame<Content: View>: View {
    var width: CGFloat = 420
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(EdgeInsets(top: 28, leading: 28, bottom: 24, trailing: 28))
            .frame(width: width, alignment: .leading)
            .background(Color.bgWindow)
            .foregroundStyle(Color.textPrimary)
            .noFocusRing()
    }
}

extension Color {
    /// 위험한 동작 버튼 바탕 (페어링 초기화)
    static let dangerFill = Color(light: 0xC41818, dark: 0xC41818)
}

/// 확인 창 버튼 (높이 36, 13pt)
struct DialogButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain, danger }
    var kind: Kind = .primary
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(height < 34 ? 12 : 13, filled ? .bold : .semibold))
            .lineLimit(1)
            .padding(.horizontal, height < 34 ? 14 : 18)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: height / 2, style: .circular).fill(background))
            .overlay(RoundedRectangle(cornerRadius: height / 2, style: .circular).strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2, style: .circular))
    }

    private var filled: Bool { kind == .primary || kind == .danger }

    private var foreground: Color {
        guard isEnabled else { return .textSecondary }
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return .brandText
        case .plain: return .textPrimary
        }
    }

    private var background: Color {
        guard isEnabled else { return .disabledFill }
        switch kind {
        case .primary: return .brandFill
        case .danger: return .dangerFill
        case .secondary, .plain: return .clear
        }
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .primary, .danger: return .clear
        case .secondary: return .brand
        case .plain: return .pillBorder
        }
    }
}

// MARK: - 연결 요청 (30초 뒤 자동 거절)

struct ConnectionRequestView: View {
    @EnvironmentObject var model: AppModel
    let name: String
    let address: String
    let handle: DialogHandle
    var seconds = 30
    @State private var remaining = 30
    @State private var answered = false

    var body: some View {
        DialogFrame {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(Color.segmentBg)
                    .frame(width: 40, height: 40)
                    .overlay(PhoneGlyph(kind: .plain)
                        .stroke(Color.textPrimary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("‘\(name)’에서 연결을 요청했어요").font(Typo.font(16, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("기본 기기가 아니에요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            (Text("허용하면 아이폰으로 넘어갔을 때 ")
                + Text("키보드와 트랙패드 입력이 이 기기로 가요.").font(Typo.font(13, .bold))
                + Text(" 새 기본 기기가 되고, 이전 기기는 목록에 남아요. 모르는 기기라면 거절하세요."))
                .font(Typo.body).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("\(remaining)초 뒤 자동으로 거절해요")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("거절") { deny(timedOut: false) }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                Button("허용") { allow() }
                    .buttonStyle(DialogButtonStyle(kind: .primary))
            }
            .padding(.top, 4)
        }
        .onAppear {
            remaining = seconds
            handle.onCancel = { deny(timedOut: false) }
            handle.onClose = { if !answered { deny(timedOut: false, closeWindow: false) } }
        }
        .task {
            while !answered {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !answered else { return }
                if remaining > 1 { remaining -= 1 } else { deny(timedOut: true) }
            }
        }
    }

    private func allow() {
        guard !answered else { return }
        answered = true
        HIDLog.info("연결 요청 허용: \(address)")
        model.acceptConnectionRequest(address: address, name: name)
        handle.close()
    }

    private func deny(timedOut: Bool, closeWindow: Bool = true) {
        guard !answered else { return }
        answered = true
        HIDLog.info(timedOut ? "연결 요청 30초 지나 거절: \(address)" : "연결 요청 거절: \(address)")
        model.showToast("‘\(name)’의 연결을 거절했어요")
        if closeWindow { handle.close() }
    }
}

// MARK: - 클립보드 보내기 확인

struct ClipboardConfirmView: View {
    @EnvironmentObject var model: AppModel
    let sendable: Int
    let skipped: Int
    let handle: DialogHandle
    /// 캡처용으로 미리보기 글을 정할 수 있다 (nil이면 지금 클립보드)
    var previewText: String? = nil
    @State private var dontAsk = false

    var body: some View {
        DialogFrame {
            Text("아이폰 입력이 영어인지 확인하세요").font(Typo.font(16, .bold))
            Text("클립보드 보내기는 글자를 하나씩 타이핑해요. 아이폰 입력이 한국어면 영문이 한글 자모로 입력돼요.")
                .font(Typo.body).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                countRow("보낼 글자", "\(sendable)자", color: .textPrimary)
                countRow("빼고 보낼 글자 (한글 등)", "\(skipped)자", color: skipped > 0 ? .warningStrong : .textPrimary)
                Text(preview)
                    .font(Typo.secondary)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.top, 4)
                    .accessibilityLabel("미리보기: \(preview)")
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
            Toggle(isOn: $dontAsk) { Text("다시 묻지 않기").font(Typo.body) }
                .toggleStyle(.checkbox)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("취소") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("보내기") {
                        handle.close()
                        model.confirmClipboardSend(dontAskAgain: dontAsk)
                    }
                    .buttonStyle(DialogButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(sendable == 0)
                }
                if sendable == 0 {
                    Text("보낼 수 있는 영문·숫자·기호가 없어요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
    }

    private func countRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value).font(Typo.font(12, .bold)).foregroundStyle(color)
        }
        .font(Typo.secondary)
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        ClipboardPreview.make(previewText ?? NSPasteboard.general.string(forType: .string) ?? "")
    }
}

/// 클립보드 미리보기: 앞부분만, 줄바꿈은 한 줄로, 비밀번호처럼 보이는 부분은 가린다.
enum ClipboardPreview {
    static func make(_ text: String, limit: Int = 60) -> String {
        var s = String(text.prefix(400))
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // pw: xxx, password=xxx, 비밀번호 xxx
        s = s.replacingOccurrences(of: #"(?i)\b(pw|pwd|pass|passwd|password|pin|token|secret|key)\s*([:=])\s*\S+"#,
                                   with: "$1$2 [가려짐]", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(비밀번호|암호|비번)\s*[:=]?\s*\S+"#, with: "$1 [가려짐]", options: .regularExpression)
        // 대문자·소문자·숫자·특수 기호(!@#$ 등)가 모두 섞인 8자 넘는 덩어리
        let special = Set("!@#$%^&*?+=~<>|;")
        let words = s.split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
            let w = String(w)
            guard w.count >= 8 else { return w }
            let upper = w.contains { $0.isUppercase }, lower = w.contains { $0.isLowercase }
            let digit = w.contains { $0.isNumber }, symbol = w.contains { special.contains($0) }
            return (upper && lower && digit && symbol) ? "[가려짐]" : w
        }
        s = words.joined(separator: " ")
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }
}

// MARK: - 단축키 겹침

struct ShortcutConflictView: View {
    @EnvironmentObject var settings: AppSettings
    let action: HotkeyAction
    let hotkey: Hotkey
    let conflictsWith: String
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.warningStrong)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    (Text("방금 기록한 ") + Text(hotkey.display).font(Typo.font(14, .heavy)) + Text(" 단축키가 겹쳐요"))
                        .font(Typo.font(14, .bold))
                    Text("‘\(conflictsWith)’에서 이미 쓰는 조합이에요. 이대로 쓰면 Mac에서 그 기능이 안 될 수 있어요.\(voiceOverNote)")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let recommended {
                HStack(spacing: 8) {
                    Text("추천 조합").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    KeyCap(text: recommended.display)
                }
                .padding(.leading, 26)
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button("추천으로 바꾸기") {
                        if let recommended { settings.hotkeys[action] = recommended }
                        handle.close()
                    }
                    .buttonStyle(DialogButtonStyle(kind: .primary, height: 32))
                    .disabled(recommendBlocked != nil)
                    .keyboardShortcut(.defaultAction)
                    Button("그대로 두기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain, height: 32))
                }
                if let recommendBlocked {
                    Text(recommendBlocked).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.leading, 26)
            .padding(.top, 4)
        }
    }

    private var recommended: Hotkey? { Hotkey.defaults[action] }

    /// 추천 조합을 쓸 수 없는 이유
    private var recommendBlocked: String? {
        guard let r = recommended else { return "이 동작은 추천 조합이 없어요" }
        if r == hotkey { return "지금 조합이 이미 추천 조합이에요" }
        if let other = settings.hotkeys.first(where: { $0.key != action && $0.value == r })?.key {
            return "추천 조합을 ‘\(other.label)’에서 쓰고 있어요"
        }
        return nil
    }

    private var voiceOverNote: String {
        let onlyCtrlOpt = hotkey.modifiers & Hotkey.all == Hotkey.control | Hotkey.option
        return onlyCtrlOpt ? " VoiceOver를 쓰고 있다면 ⌃⌥만 쓰는 조합도 피해주세요." : ""
    }
}

// MARK: - 페어링 초기화

struct ResetPairingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 16) {
            Text("페어링을 초기화할까요?").font(Typo.font(16, .bold))
            VStack(alignment: .leading, spacing: 8) {
                (Text("지워지는 것: ").font(Typo.bodyBold)
                    + Text("기본 기기(\(settings.lastDeviceName ?? "없음")), 아이폰을 놓은 자리, 버튼 등록 기록, 처음 설정 진행"))
                    .fixedSize(horizontal: false, vertical: true)
                (Text("남는 것: ").font(Typo.bodyBold) + Text("단축키, 보정값, 기기 모델·방향 등 다른 설정"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Typo.body).lineSpacing(4)
            VStack(alignment: .leading, spacing: 6) {
                Text("초기화한 뒤 해야 할 일").font(Typo.font(12, .bold))
                Text("1. Mac: 시스템 설정 › 블루투스에서 아이폰 옆 ⓘ › 이 기기 지우기")
                Text("2. 아이폰: 설정 › Bluetooth에서 이 Mac 옆 ⓘ › 이 기기 지우기")
                Text("3. EdgeLink에서 다시 페어링")
            }
            .font(Typo.secondary).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
            HStack(spacing: 8) {
                Spacer()
                Button("취소") { handle.close() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                Button("초기화") {
                    handle.close()
                    model.resetPairing()
                }
                .buttonStyle(DialogButtonStyle(kind: .danger))
                .accessibilityHint("기본 기기와 페어링 기록을 지워요")
            }
            .padding(.top, 4)
        }
    }
}
