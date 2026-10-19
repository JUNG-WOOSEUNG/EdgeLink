import AppKit
import EdgeLinkCore
import SwiftUI

/// 연결 로그 보기 (캔버스 4-4). 최근 500줄, 오류 줄 강조, 복사할 때 주소 뒷자리 가림.
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
                Text(verbatim: "복사할 때 기기 주소 뒷자리는 가려져요 (A4:83:5C:**:**:**)")
                    .font(Typo.caption).foregroundStyle(Color.textSecondary)
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
            .frame(height: 260)
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
        let text = (fixedLines.map { $0.map(HIDLog.maskAddress) } ?? HIDLog.recent(maskAddresses: true)).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

/// "10:20:01.123 [ERROR] 내용" 한 줄
private struct LogRow: View {
    let line: String

    var body: some View {
        let p = parsed
        (Text(p.time).foregroundColor(.textSecondary)
            + Text("  ")
            + Text(p.tag.map { "\($0) " } ?? "").foregroundColor(p.color)
            + Text(p.message).foregroundColor(p.color))
            .font(.system(size: 11, weight: p.isError ? .bold : .regular, design: .monospaced))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parsed: (time: String, tag: String?, message: String, color: Color, isError: Bool) {
        // 시각은 초까지만 보여준다
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[1].hasPrefix("["), parts[1].hasSuffix("]") else {
            return ("", nil, line, .textPrimary, false)
        }
        let time = String(parts[0].prefix(8))
        switch parts[1] {
        case "[ERROR]": return (time, "오류", parts[2], .dangerText, true)
        case "[WARN]": return (time, "주의", parts[2], .warningStrong, false)
        default: return (time, nil, parts[2], .textPrimary, false)
        }
    }
}
