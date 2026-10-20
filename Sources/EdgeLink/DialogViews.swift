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
            .padding(24)
            .frame(width: width, alignment: .leading)
            .background(Color.bgWindow)
            .foregroundStyle(Color.textPrimary)
            .noFocusRing()
    }
}

extension Color {
    /// 위험한 동작 버튼 바탕 (페어링 초기화). 다크에서는 바탕 없이 테두리만 쓴다.
    static let dangerFill = Color(light: 0xC41818, dark: 0xC41818)
    /// 다크 위험 버튼 테두리·글자 (캔버스 다크 모드)
    static let dangerOutlineDark = Color(hex: 0xFF6B6B)
    static let dangerLabelDark = Color(hex: 0xFF8A8A)
}

/// 받침에 따라 조사를 고른다 ("‘지민의 iPhone’이", "⌃⌥Space가").
/// 한글은 마지막 글자의 받침, 영문·숫자는 읽는 소리(엘·엠·엔·알, 영·일·삼·육·칠·팔)로 판단한다.
enum Josa {
    static func hasBatchim(_ word: String) -> Bool {
        guard let last = word.reversed().first(where: { $0.isLetter || $0.isNumber }) else { return false }
        if let v = last.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v) {
            return (v - 0xAC00) % 28 != 0
        }
        let lower = String(last).lowercased()
        let word = word.lowercased()
        // 흔한 영어 낱말 끝 (Phone, Pad, Mac, Air, Pro …)
        for (suffix, batchim) in [("phone", true), ("pad", true), ("mac", true), ("book", true), ("air", false),
                                  ("pro", false), ("max", false), ("mini", false), ("plus", false), ("space", false)]
        where word.hasSuffix(suffix) { return batchim }
        return ["l", "m", "n", "r", "0", "1", "3", "6", "7", "8"].contains(lower)
    }

    /// 이/가
    static func iGa(_ word: String) -> String { hasBatchim(word) ? "이" : "가" }
    /// 과/와
    static func gwaWa(_ word: String) -> String { hasBatchim(word) ? "과" : "와" }
}

extension String {
    /// 줄바꿈되지 않게 띄어쓰기를 U+00A0으로 바꾼다 (짧은 이름·낱말 묶음)
    var nonBreaking: String { replacingOccurrences(of: " ", with: "\u{00A0}") }
}

/// 확인 창 버튼 (높이 36, 13pt)
struct DialogButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain, danger }
    var kind: Kind = .primary
    var height: CGFloat = 36
    /// 꺼졌을 때 회색 대신 원래 모양 그대로 흐리게 (불투명도 0.4). 왜 꺼졌는지 아래에 적어 둘 때 쓴다.
    var dimWhenDisabled = false
    @Environment(\.isEnabled) private var isEnabledEnv
    @Environment(\.colorScheme) private var colorScheme

    /// 흐리게 그릴 때는 켜진 모양으로 색을 고른다
    private var isEnabled: Bool { isEnabledEnv || dimWhenDisabled }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(height < 34 ? 12 : 13, filled ? .bold : .semibold))
            .lineLimit(1)
            .padding(.horizontal, height < 34 ? 14 : 18)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: height / 2, style: .circular).fill(background))
            .overlay(RoundedRectangle(cornerRadius: height / 2, style: .circular).strokeBorder(border, lineWidth: 1))
            .opacity(!isEnabledEnv ? 0.4 : configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2, style: .circular))
    }

    /// 다크의 위험 버튼은 바탕 없이 테두리만 (캔버스 다크 모드 "페어링 초기화")
    private var darkDanger: Bool { kind == .danger && colorScheme == .dark }
    private var filled: Bool { kind == .primary || (kind == .danger && !darkDanger) }

    private var foreground: Color {
        guard isEnabled else { return .textSecondary }
        switch kind {
        case .danger: return darkDanger ? .dangerLabelDark : .white
        case .primary: return .white
        case .secondary: return .brandText
        case .plain: return .textPrimary
        }
    }

    private var background: Color {
        guard isEnabled else { return .disabledFill }
        switch kind {
        case .primary: return .brandFill
        case .danger: return darkDanger ? .clear : .dangerFill
        case .secondary, .plain: return .clear
        }
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .primary: return .clear
        case .danger: return darkDanger ? .dangerOutlineDark : .clear
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
                    Text("‘\(name)’\(Josa.iGa(name)) 연결하려고 해요").font(Typo.font(16, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("기본 기기가 아니에요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            (Text("허용하면 아이폰으로 넘어갔을 때 ")
                + Text("키보드와 트랙패드 입력이 \("이 기기로 가요.".nonBreaking)").font(Typo.font(13, .bold))
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
                ClipboardPreview.styled(preview)
                    .font(.system(size: 12, design: .monospaced))
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
    static let masked = "[가려짐]"

    /// 보낼 글자는 진하게, 빠지는 글자(한글 등)는 흐리게, 가린 곳은 보조 색으로
    static func styled(_ preview: String) -> Text {
        var result = Text("")
        var run = "", runKind = 0   // 0 보냄, 1 빠짐
        func flush() {
            guard !run.isEmpty else { return }
            result = result + Text(verbatim: run).foregroundColor(runKind == 0 ? .textPrimary : .textDecor)
            run = ""
        }
        var rest = Substring(preview)
        while let ch = rest.first {
            if rest.hasPrefix(masked) {
                flush()
                result = result + Text(verbatim: masked).foregroundColor(.textSecondary)
                rest = rest.dropFirst(masked.count)
                continue
            }
            // "…"는 잘렸다는 표시라 보내는 글자처럼 둔다
            let kind = (ch == "…" || HIDUsage.fromASCII(ch) != nil) ? 0 : 1
            if kind != runKind { flush(); runKind = kind }
            run.append(ch)
            rest = rest.dropFirst()
        }
        flush()
        return result
    }

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

/// 기록기는 겹치는 조합을 저장하지 않고 이 창을 부른다. "그래도 쓰기"를 눌러야 저장한다.
struct ShortcutConflictView: View {
    @EnvironmentObject var settings: AppSettings
    let action: HotkeyAction
    let hotkey: Hotkey
    let conflictsWith: String
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.warningStrong)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Typo.font(13, .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 8) {
                    Button("다른 조합 고르기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .primary, height: 32))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint("저장하지 않고 닫아요. 단축키를 다시 기록하세요.")
                    Button("그래도 쓰기") { useAnyway() }
                        .buttonStyle(DialogButtonStyle(kind: .plain, height: 32))
                        .accessibilityHint("\(hotkey.display)를 저장해요")
                }
                .padding(.leading, 25)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.bgWindow))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.warningLine, lineWidth: 1))
        }
    }

    /// "방금 기록한 ⌃⌥Space가 입력 소스 전환과 겹쳐요"
    private var title: String {
        let key = hotkey.display
        return "방금 기록한 \(key)\(Josa.iGa(key)) \(conflictsWith.nonBreaking)\(Josa.gwaWa(conflictsWith)) 겹쳐요"
    }

    private var message: String {
        "이대로 쓰면 Mac에서 \(conflictsWith.nonBreaking)\(Josa.iGa(conflictsWith)) 안 될 수 있어요.\(voiceOverNote)"
    }

    private func useAnyway() {
        settings.hotkeys[action] = hotkey
        // 제스처를 대신하는 단축키는 저장하면서 켠다
        if let g = action.gesture, var s = settings.gestureMap[g] {
            s.hotkeyEnabled = true
            settings.gestureMap[g] = s
        }
        handle.close()
    }

    private var voiceOverNote: String {
        let onlyCtrlOpt = hotkey.modifiers & Hotkey.all == Hotkey.control | Hotkey.option
        return onlyCtrlOpt ? " VoiceOver를 쓰고 있다면 ⌃⌥만 쓰는 조합도 피해 주세요." : ""
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
                    + Text("기본 기기(\((settings.lastDeviceName ?? "없음").nonBreaking)), \("기기별 모델·방향".nonBreaking), \("버튼 등록 기록".nonBreaking)"))
                    .fixedSize(horizontal: false, vertical: true)
                (Text("남는 것: ").font(Typo.bodyBold) + Text("단축키, 배치, 보정값 등 \("다른 설정".nonBreaking)"))
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

// MARK: - 업데이트

/// 새 버전 알림. 내려받기·설치 진행도 이 창에서 보여준다.
struct UpdateView: View {
    @ObservedObject var updater: Updater
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 14) {
            switch updater.state {
            case let .available(release):
                Text("새 버전 \(release.version)이 나왔어요").font(Typo.font(16, .bold))
                Text("지금 버전은 \(Updater.currentVersion)이에요. 설치하면 EdgeLink가 잠깐 꺼졌다 다시 켜져요.")
                    .font(Typo.body).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !release.notes.isEmpty { notes(release.notes) }
                buttons {
                    if let page = release.pageURL {
                        Button("자세히") { NSWorkspace.shared.open(page) }
                            .buttonStyle(DialogButtonStyle(kind: .plain))
                    }
                    Spacer()
                    Button("나중에") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("업데이트") { updater.install() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            case let .downloading(progress):
                Text("내려받는 중…").font(Typo.font(16, .bold))
                ProgressView(value: progress).tint(Color.brandFill)
                buttons {
                    Spacer()
                    Button("취소") { updater.cancelDownload() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                }
            case .installing:
                Text("설치하는 중…").font(Typo.font(16, .bold))
                ProgressView().progressViewStyle(.linear).tint(Color.brandFill)
                Text("서명을 확인한 뒤 다시 켜요.").font(Typo.secondary).foregroundStyle(Color.textSecondary)
            case let .failed(message):
                Text("업데이트하지 못했어요").font(Typo.font(16, .bold))
                Text(message).font(Typo.body).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                buttons {
                    Spacer()
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            default:
                Text("최신 버전이에요").font(Typo.font(16, .bold))
                buttons {
                    Spacer()
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func notes(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(Typo.secondary).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
    }

    private func buttons<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }.padding(.top, 4)
    }
}
