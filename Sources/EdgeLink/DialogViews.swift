import AppKit
import EdgeLinkCore
import SwiftUI

// 확인 창 내용 (캔버스 4-1 연결 요청·클립보드·단축키 겹침, 4-4 페어링 초기화)

/// 확인 창 공통 틀: 너비 420, 가장자리 xl(24), 덩어리 사이 l(16)
/// 글은 왼쪽 정렬, 버튼 줄은 `DialogButtonRow`로 주 버튼을 맨 오른쪽에 둔다.
struct DialogFrame<Content: View>: View {
    var width: CGFloat = 420
    var spacing: CGFloat = Space.l
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(Space.xl)
            .frame(width: width, alignment: .leading)
            .background(Color.bgWindow)
            .foregroundStyle(Color.textPrimary)
            .noFocusRing()
    }
}

/// 확인 창 제목 (16pt 굵게). 궁금할 때만 볼 설명은 제목 오른쪽 ⓘ로 접는다.
struct DialogTitle: View {
    let text: String
    var info: String? = nil

    init(_ text: String, info: String? = nil) {
        self.text = text
        self.info = info
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(text).font(Typo.font(16, .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let info { InfoTip(info) }
        }
    }
}

/// 확인 창 맨 아래 버튼 줄. 왼쪽에는 짧은 안내(남은 시간, 버튼이 꺼진 이유), 버튼은 오른쪽 끝에 모으고
/// 주 버튼을 맨 마지막(맨 오른쪽)에 넣는다.
struct DialogButtonRow<Buttons: View>: View {
    var note: String? = nil
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(spacing: Space.s) {
            if let note {
                Text(note).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            buttons
        }
        .padding(.top, Space.xs)
    }
}

/// 결과·경고 한 덩어리: 아이콘(첫 줄에 맞춤) + 제목 + 설명. 완료·실패·겹침 창이 같은 모양을 쓴다.
struct DialogStatus: View {
    let systemImage: String
    let color: Color
    let title: String
    var message: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.font(14, .bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// 회색 바탕 묶음 (확인 창 안 목록·미리보기). 안쪽 여백 세로 m, 가로 l.
struct DialogBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
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
            HStack(spacing: Space.m) {
                RoundedRectangle(cornerRadius: 10).fill(Color.segmentBg)
                    .frame(width: 40, height: 40)
                    .overlay(PhoneGlyph(kind: .plain)
                        .stroke(Color.textPrimary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("‘\(name)’\(Josa.iGa(name)) 연결하려고 해요").font(Typo.font(16, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.xs) {
                        Text("기본 기기가 아니에요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        // 허용한 뒤 어떻게 되는지는 궁금할 때만
                        InfoTip("허용하면 이 기기가 새 기본 기기가 돼요. 이전 기본 기기는 목록에 그대로 남아요.")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            (Text("허용하면 ")
                + Text("키보드·트랙패드 입력이 \("이 기기로 가요.".nonBreaking)").font(Typo.font(13, .bold))
                // 두 번째 문장은 한 덩어리로 넘겨 끝에 한두 낱말만 남지 않게
                + Text(" " + "모르는 기기라면 거절하세요.".nonBreaking))
                .font(Typo.body).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow(note: "\(remaining)초 뒤 자동으로 거절해요") {
                Button("거절") { deny(timedOut: false) }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                Button("허용") { allow() }
                    .buttonStyle(DialogButtonStyle(kind: .primary))
            }
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
            VStack(alignment: .leading, spacing: Space.s) {
                // 왜 영어여야 하는지는 ⓘ로. 화면에는 할 일만 남긴다.
                DialogTitle("아이폰 입력이 영어인지 확인하세요",
                            info: "클립보드 보내기는 글자를 하나씩 타이핑해요. 아이폰 입력이 한국어면 영문이 한글 자모로 입력돼요.")
                Text("아이폰 키보드를 영어로 바꾼 뒤 보내세요.")
                    .font(Typo.body).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DialogBox {
                VStack(alignment: .leading, spacing: Space.s) {
                    countRow("보낼 글자", "\(sendable)자", color: .textPrimary)
                    countRow("보내지 않는 글자 (한글 등)", "\(skipped)자", color: skipped > 0 ? .warningStrong : .textPrimary)
                    ClipboardPreview.styled(preview)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.top, Space.xs)
                        .accessibilityLabel("미리보기: \(preview)")
                    if skipped > 0 {
                        Text("회색 글자는 보내지 않아요").font(Typo.caption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            HStack(spacing: Space.xs) {
                Toggle(isOn: $dontAsk) { Text("다시 묻지 않기").font(Typo.body) }
                    .toggleStyle(BoxCheckboxStyle())
                    .fixedSize()
                // 빠지는 글자가 있으면 이 설정과 상관없이 다시 묻는다 (requestClipboardSend)
                InfoTip("보내지 않는 글자가 있을 때는 이 설정과 상관없이 다시 물어요.")
            }
            DialogButtonRow(note: sendable == 0 ? "보낼 수 있는 영문·숫자·기호가 없어요" : nil) {
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
        DialogFrame {
            DialogStatus(systemImage: "exclamationmark.triangle", color: .warningStrong, title: title, message: message)
            // 주 버튼(다른 조합 고르기)은 맨 오른쪽, 되돌리기 어려운 "그래도 쓰기"는 그 왼쪽
            DialogButtonRow {
                Button("그래도 쓰기") { useAnyway() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                    .accessibilityHint("\(hotkey.display)를 저장해요")
                Button("다른 조합 고르기") { handle.close() }
                    .buttonStyle(DialogButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("저장하지 않고 닫아요. 단축키를 다시 기록하세요.")
            }
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
        // 따로 한 줄로 (문장 중간에서 줄이 갈리지 않게)
        return onlyCtrlOpt ? "\nVoiceOver를 쓰고 있다면 ⌃⌥만 쓰는 조합도 피해 주세요." : ""
    }
}

// MARK: - 페어링 초기화

struct ResetPairingView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let handle: DialogHandle

    var body: some View {
        DialogFrame {
            DialogTitle("페어링을 초기화할까요?")
            // 이름표 열을 맞춰 두 줄로 넘어가도 내용끼리 시작선이 같게
            VStack(alignment: .leading, spacing: Space.s) {
                summaryRow("지워지는 것",
                           "기본 기기(\((settings.lastDeviceName ?? "없음").nonBreaking)), \("기기별 모델·방향".nonBreaking), \("트랙패드 제스처 등록".nonBreaking)")
                summaryRow("남는 것", "단축키, 배치, 돌아오는 위치 등 \("다른 설정".nonBreaking)")
            }
            DialogBox {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("초기화한 뒤 해야 할 일").font(Typo.font(12, .bold))
                    Text("1. Mac: 시스템 설정 › Bluetooth에서 아이폰 옆 ⓘ › 이 기기 지우기")
                    Text("2. 아이폰: 설정 › Bluetooth에서 이 Mac 옆 ⓘ › 이 기기 지우기")
                    Text("3. EdgeLink에서 다시 페어링하기")
                }
                .font(Typo.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
            DialogButtonRow {
                Button("취소") { handle.close() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                Button("초기화") {
                    handle.close()
                    model.resetPairing()
                }
                .buttonStyle(DialogButtonStyle(kind: .danger))
                .accessibilityHint("기본 기기와 페어링 기록을 지워요")
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(label).font(Typo.bodyBold)
                .frame(width: 70, alignment: .leading)
            Text(value).font(Typo.body).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 업데이트

/// 새 버전 알림. 내려받기·설치 진행도 이 창에서 보여준다.
struct UpdateView: View {
    @ObservedObject var updater: Updater
    let handle: DialogHandle

    var body: some View {
        DialogFrame {
            switch updater.state {
            case let .available(release):
                VStack(alignment: .leading, spacing: Space.s) {
                    DialogTitle("새 버전 \(release.version)\(Josa.iGa(release.version)) 나왔어요")
                    Text("지금 버전은 \(Updater.currentVersion)이에요. 설치하면 EdgeLink가 잠깐 꺼졌다 다시 켜져요.")
                        .font(Typo.body).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !release.notes.isEmpty { notes(release.notes) }
                HStack(spacing: Space.s) {
                    // 창 밖으로 나가는 보조 동작은 왼쪽 끝에 따로
                    if let page = release.pageURL {
                        Button("자세히") { NSWorkspace.shared.open(page) }
                            .buttonStyle(DialogButtonStyle(kind: .plain))
                    }
                    Spacer(minLength: 0)
                    Button("나중에") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("업데이트") { updater.install() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, Space.xs)
            case let .downloading(progress):
                DialogTitle("내려받는 중…")
                ProgressView(value: progress).tint(Color.brandFill)
                DialogButtonRow {
                    Button("취소") { updater.cancelDownload() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                }
            case .installing:
                VStack(alignment: .leading, spacing: Space.s) {
                    DialogTitle("설치하는 중…")
                    Text("서명을 확인한 뒤 다시 켜요.").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                ProgressView().progressViewStyle(.linear).tint(Color.brandFill)
            case let .failed(message):
                VStack(alignment: .leading, spacing: Space.s) {
                    DialogTitle("업데이트하지 못했어요")
                    Text(message).font(Typo.body).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DialogButtonRow {
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            default:
                DialogTitle("최신 버전이에요")
                DialogButtonRow {
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// **굵게**, `코드` 같은 줄 안 마크다운만
    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private func notes(_ text: String) -> some View {
        ScrollView {
            // 마크다운 기호(##, -)를 그대로 보이지 않게: 제목은 굵게, 목록은 글머리표
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(ReleaseNotes.lines(text).enumerated()), id: \.offset) { i, line in
                    switch line {
                    case let .heading(t):
                        Text(Self.inline(t)).font(Typo.font(12, .bold)).padding(.top, i == 0 ? 0 : Space.xs)
                    case let .bullet(t):
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text("•")
                            Text(Self.inline(t)).fixedSize(horizontal: false, vertical: true)
                        }
                    case let .text(t):
                        Text(Self.inline(t)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(Typo.secondary).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
        }
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
    }
}
