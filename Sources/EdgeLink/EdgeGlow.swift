import AppKit
import EdgeLinkCore
import QuartzCore

/// 모서리 효과가 붙을 자리 (Cocoa 좌표)
struct GlowPlacement: Equatable {
    var screen: ScreenRect
    var edge: ScreenEdge
    var passage: EdgeSegment
}

/// 통로를 밀 때 화면 가장자리에 붙어 튀어나오는 반투명 유리 알약 (설계 문서 › 모서리 효과 수치, 캔버스 모서리 효과 · 움직임 시안).
/// 알약 절반은 화면 밖에 있다: 창은 화면 안쪽 띠만 덮고, 알약은 창 바깥 경계에 중심을 두어 잘린다.
/// 클릭을 가로채지 않는 투명 패널. 메인 스레드에서만 부른다.
final class EdgeGlow {
    /// 창 두께 = 가장 두꺼운 단계(34pt)보다 조금 넉넉하게
    private static let bandDepth: CGFloat = 40

    private var panel: NSPanel?
    private let pill = PillView()
    private var placement: GlowPlacement?
    private var along: Double = 0
    private var fadeWork: DispatchWorkItem?
    private var phaseWork: DispatchWorkItem?
    private var generation = 0

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: 단계

    /// 미는 중: 손을 그대로 따라간다. 멈추면 0.25초 뒤 0.25초 동안 사라진다.
    func push(progress: Double, along: Double, at placement: GlowPlacement) {
        cancelPending()
        prepare(placement, along: along)
        apply(.push(progress: progress), animated: false)
        let gen = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen else { return }
            self.fadeOut(duration: self.reduceMotion ? GlowMetrics.reducedMotionDuration : GlowMetrics.pauseFade)
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GlowMetrics.pauseDelay, execute: work)
    }

    /// 넘어가는 순간(0.12초) → 아이폰 조작 중(0.28초, 계속 보임)
    func enter(along: Double, at placement: GlowPlacement) {
        cancelPending()
        prepare(placement, along: along)
        apply(.enter, animated: true)
        let gen = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen else { return }
            self.apply(.docked, animated: true)
        }
        phaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GlowMetrics.metrics(.enter, passageLength: placement.passage.length).duration, execute: work)
    }

    /// 돌아오는 순간(0.1초) → 사라짐(0.3초)
    func returned(along: Double, at placement: GlowPlacement) {
        cancelPending()
        prepare(placement, along: along)
        apply(.returning, animated: true)
        let gen = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen else { return }
            self.apply(.gone, animated: true) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.panel?.orderOut(nil)
            }
        }
        phaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GlowMetrics.metrics(.returning, passageLength: placement.passage.length).duration, execute: work)
    }

    /// 효과 없이 바로 감춘다 (모니터 구성 변경, 유리 효과 끔)
    func hide() {
        cancelPending()
        generation += 1
        panel?.orderOut(nil)
    }

    // MARK: 그리기

    private func cancelPending() {
        fadeWork?.cancel(); fadeWork = nil
        phaseWork?.cancel(); phaseWork = nil
    }

    private func prepare(_ p: GlowPlacement, along: Double) {
        generation += 1
        self.along = along
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if placement != p {
            placement = p
            panel.setFrame(bandFrame(p), display: false)
            pill.isVertical = p.edge.isVertical
        }
        pill.isDark = NSApp.effectiveAppearance.isDark
        if !panel.isVisible {
            pill.alphaValue = 0
            panel.orderFrontRegardless()
        }
    }

    /// 화면 안쪽 띠 (통로 길이만큼)
    private func bandFrame(_ p: GlowPlacement) -> NSRect {
        let d = Self.bandDepth
        let s = p.screen, a = p.passage
        switch p.edge {
        case .right: return NSRect(x: s.maxX - d, y: a.start, width: d, height: a.length)
        case .left: return NSRect(x: s.x, y: a.start, width: d, height: a.length)
        case .top: return NSRect(x: a.start, y: s.maxY - d, width: a.length, height: d)
        case .bottom: return NSRect(x: a.start, y: s.y, width: a.length, height: d)
        }
    }

    /// 알약 위치 (창 안 좌표). 너비는 두께의 2배, 절반은 창(=화면) 밖.
    private func pillFrame(_ m: GlowMetrics, _ p: GlowPlacement) -> NSRect {
        let d = Self.bandDepth
        let b = CGFloat(m.thickness), l = CGFloat(m.length)
        let c = CGFloat(GlowMetrics.center(along: along, length: m.length, passage: p.passage) - p.passage.start)
        switch p.edge {
        case .right: return NSRect(x: d - b, y: c - l / 2, width: b * 2, height: l)
        case .left: return NSRect(x: -b, y: c - l / 2, width: b * 2, height: l)
        case .top: return NSRect(x: c - l / 2, y: d - b, width: l, height: b * 2)
        case .bottom: return NSRect(x: c - l / 2, y: -b, width: l, height: b * 2)
        }
    }

    private func apply(_ phase: GlowPhase, animated: Bool, completion: (() -> Void)? = nil) {
        guard let p = placement else { completion?(); return }
        let reduce = reduceMotion
        let m = GlowMetrics.metrics(phase, passageLength: p.passage.length, reduceMotion: reduce)
        let frame = pillFrame(m, p)
        guard animated, m.duration > 0 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pill.frame = frame
            pill.alphaValue = CGFloat(m.opacity)
            CATransaction.commit()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = m.duration
            let c = GlowMetrics.curve
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: Float(c.0), Float(c.1), Float(c.2), Float(c.3))
            ctx.allowsImplicitAnimation = true
            // 동작 줄이기: 크기는 그대로, 불투명도만
            if reduce { pill.frame = frame } else { pill.animator().frame = frame }
            pill.animator().alphaValue = CGFloat(m.opacity)
        }, completionHandler: completion)
    }

    private func fadeOut(duration: Double) {
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            pill.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == gen else { return }
            self.panel?.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true          // 클릭을 가로채지 않음
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.animationBehavior = .none
        let content = NSView()
        content.wantsLayer = true
        content.layer?.masksToBounds = true  // 알약 절반(화면 밖 쪽)을 자른다
        content.addSubview(pill)
        p.contentView = content
        return p
    }
}

/// 유리 알약: 흐림 + Innovation Blue 틴트 16%(어두운 배경 24%) + 흰 테두리 50%(어두운 배경 35%)
private final class PillView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()

    var isVertical = true { didSet { needsLayout = true } }
    var isDark = false { didSet { if isDark != oldValue { updateColors() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(blur)
        addSubview(tint)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        // 알약: 짧은 쪽의 절반이 둥글기
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layer?.cornerRadius = min(newSize.width, newSize.height) / 2
    }

    private func updateColors() {
        let brand = NSColor(hex: 0x0097E4)
        tint.layer?.backgroundColor = brand.withAlphaComponent(isDark ? 0.24 : 0.16).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.35 : 0.5).cgColor
    }
}
