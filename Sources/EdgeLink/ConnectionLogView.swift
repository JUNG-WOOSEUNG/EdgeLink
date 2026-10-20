import AppKit
import EdgeLinkCore
import SwiftUI

/// 연결 로그 보기 (캔버스 4-4). 최근 500줄, 오류 줄 강조, 복사할 때 주소 뒷자리 가림.
/// 기기 주소는 화면·복사·안내 문구 모두 "A4:83:5C:12:34:56" 한 가지 모양으로 보여준다.
struct ConnectionLogView: View {
    let handle: DialogHandle
    /// 캡처용 (nil이면 HIDLog에서 읽고 1초마다 새로 읽는다)
    var fixedLines: [String]? = nil
    @State private var lines: [String] = []
    @State private var copied = false

    var body: some View {
        DialogFrame(width: 560, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("연결 로그").font(Typo.font(16, .bold))
                Spacer()
                Text("최근 \(HIDLog.capacity)줄 · 키 입력 내용은 남기지 않아요")
                    .font(Typo.caption).foregroundStyle(Color.textSecondary)
            }
            logBox
            HStack(spacing: 8) {
                // 이 로그를 어디에 쓰는지 알린다
                Text("문제를 알릴 때 ‘복사’해서 붙여 주세요 · 기기 주소 뒷자리는 가려져요")
                    .font(Typo.caption).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied ? "복사했어요" : "복사") { copy() }
                    .buttonStyle(DialogButtonStyle(kind: .secondary, height: 32))
                    .disabled(lines.isEmpty)
                Button("닫기") { handle.close() }
                    .buttonStyle(DialogButtonStyle(kind: .primary, height: 32))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .onAppear { reload() }
        .task {
            guard fixedLines == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                reload()
            }
        }
    }

    private var logBox: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lines.isEmpty {
                    Text("아직 기록이 없어요. 연결을 시도하면 여기에 남아요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            LogRow(line: line).id(i)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .frame(minHeight: 200, idealHeight: 260, maxHeight: 260)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
            .onChange(of: lines.count) { n in
                if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
            }
            .onAppear { if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) } }
        }
        .accessibilityLabel("연결 로그 \(lines.count)줄")
    }

    private func reload() {
        let next = fixedLines ?? HIDLog.recent()
        if next != lines { lines = next }
    }

    private func copy() {
        let text = (fixedLines ?? HIDLog.recent()).map { LogText.mask(LogText.normalize($0)) }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

/// 로그 글을 화면·복사에 맞게 다듬는다
enum LogText {
    private static let address = #"([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})[:-]([0-9A-Fa-f]{2})"#

    /// 기기 주소를 대문자·쌍점 모양으로 맞춘다 ("a4-83-5c-…" → "A4:83:5C:…")
    static func normalize(_ line: String) -> String {
        guard let re = try? NSRegularExpression(pattern: address) else { return line }
        var out = line
        for m in re.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
            guard let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: out[r].replacingOccurrences(of: "-", with: ":").uppercased())
        }
        return out
    }

    /// 앞 세 자리만 남기고 가린다 ("A4:83:5C:**:**:**")
    static func mask(_ line: String) -> String {
        line.replacingOccurrences(of: address, with: "$1:$2:$3:**:**:**", options: .regularExpression)
    }

    /// 개발자 말을 사용자 말로 (로그 원문은 그대로 두고 화면에서만)
    static func friendly(_ message: String) -> String {
        message.replacingOccurrences(of: #"쓰기 지연 (\d+)\s*ms"#, with: "응답이 $1ms 늦었어요", options: .regularExpression)
    }
}

/// "10:20:01.123 [ERROR] 내용" 한 줄
private struct LogRow: View {
    let line: String

    var body: some View {
        let p = parsed
        // 오류 줄은 내용만 빨강 굵게 (시각은 그대로)
        let body = Font.system(size: 11, weight: p.isError ? .bold : .regular, design: .monospaced)
        (Text(p.time).foregroundColor(.textSecondary)
            + Text("  ")
            + Text(p.tag.map { "\($0) · " } ?? "").font(body).foregroundColor(p.color)
            + Text(verbatim: p.message).font(body).foregroundColor(p.color))
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parsed: (time: String, tag: String?, message: String, color: Color, isError: Bool) {
        // 시각은 초까지만 보여준다
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[1].hasPrefix("["), parts[1].hasSuffix("]") else {
            return ("", nil, LogText.normalize(line), .textPrimary, false)
        }
        let time = String(parts[0].prefix(8))
        let message = LogText.friendly(LogText.normalize(parts[2]))
        switch parts[1] {
        case "[ERROR]": return (time, "오류", message, .dangerText, true)
        case "[WARN]": return (time, "주의", message, .warningStrong, false)
        default: return (time, nil, message, .textPrimary, false)
        }
    }
}
