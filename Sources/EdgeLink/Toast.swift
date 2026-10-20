import AppKit
import SwiftUI

/// 화면 위쪽 가운데 알림, 2.5초 (캔버스 4-2). 클립보드 보내는 중 진행 알림도 같은 자리에 뜬다 (캔버스 4-4).
/// 커서가 있는 화면에 뜨고, 여러 개가 오면 마지막 것으로 바꾼다. 클릭은 아래 창으로 통과한다.
/// 메인 스레드에서 부른다 (다른 스레드에서 부르면 메인으로 넘긴다).
final class ToastCenter {
    static let duration: TimeInterval = 2.5
    static let fade: TimeInterval = 0.2
    /// 메뉴 막대 아래로 띄우는 거리
    static let topMargin: CGFloat = 12

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    func show(_ text: String, systemImage: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(text, systemImage: systemImage) }
            return
        }
        present(AnyView(ToastView(text: text, systemImage: systemImage)), autoHide: Self.duration)
    }

    /// 클립보드 보내는 중 진행 알림. 끝날 때는 `show("보냈어요")`로 바꾼다.
    func showProgress(title: String, remaining: Int, fraction: Double, footnote: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.showProgress(title: title, remaining: remaining, fraction: fraction, footnote: footnote) }
            return
        }
        // 진행 중에는 사라지지 않는다 (다음 갱신이나 끝 알림이 바꾼다)
        present(AnyView(ProgressToastView(title: title, remaining: remaining, fraction: fraction, footnote: footnote)),
                autoHide: nil)
    }

    func hide() {
        guard Thread.isMainThread else { return DispatchQueue.main.async { self.hide() } }
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func present(_ content: AnyView, autoHide: TimeInterval?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        generation += 1
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // 커서가 있는 화면 위쪽 가운데 (메뉴 막대 아래)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let area = screen.visibleFrame
            let origin = NSPoint(x: (area.midX - size.width / 2).rounded(), y: (area.maxY - Self.topMargin - size.height).rounded())
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        guard let autoHide else { return }
        let gen = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.fade
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.panel?.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true          // 클릭 통과
        p.level = .statusBar
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.animationBehavior = .none
        return p
    }
}

// MARK: - 화면

/// hudWindow 흐림 배경, 둥글기 12
private struct ToastBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension View {
    func toastChrome() -> some View {
        self
            .background(ToastBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.line.opacity(0.6), lineWidth: 1))
            .padding(1)
    }
}

private struct ToastView: View {
    let text: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Typo.font(13, .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .frame(maxWidth: 420)
        .fixedSize()
        .toastChrome()
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressToastView: View {
    let title: String
    let remaining: Int
    let fraction: Double
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title).font(Typo.font(13, .bold))
                Spacer(minLength: Space.s)
                Text("\(remaining)자 남음").font(Typo.secondary).foregroundStyle(Color.textSecondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.line)
                    Capsule().fill(Color.brand).frame(width: g.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(footnote).font(Typo.caption).foregroundStyle(Color.textSecondary)
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .frame(width: 380)
        .toastChrome()
        .accessibilityElement(children: .combine)
    }
}
