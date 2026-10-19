import Foundation

/// 모니터 모서리와 통로(파란 구간) 계산. 좌표는 Cocoa 기준(아래쪽이 y 0), 단위 pt.
public enum ScreenEdge: String, Codable, CaseIterable {
    case left, right, top, bottom

    public var isVertical: Bool { self == .left || self == .right }

    public var label: String {
        switch self {
        case .left: return "왼쪽"
        case .right: return "오른쪽"
        case .top: return "위"
        case .bottom: return "아래"
        }
    }
}

public struct ScreenRect: Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// 모서리를 따라가는 구간. 세로 모서리는 y, 가로 모서리는 x 좌표.
public struct EdgeSegment: Equatable {
    public var start: Double, end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
    public var length: Double { end - start }
}

public enum LayoutGeometry {
    /// 꼭짓점에서 이만큼은 핫 코너라서 통로에서 뺀다.
    public static let cornerInset: Double = 24
    /// 통로가 이보다 짧으면 그 자리에는 놓을 수 없다.
    public static let minimumPassage: Double = 60
    /// 이 거리 안이면 두 모니터가 맞닿았다고 본다.
    static let touchTolerance: Double = 1

    /// 통로 = 모서리 ∩ 다른 모니터와 맞닿지 않은 구간 − 꼭짓점 24pt. 60pt 이상인 구간만.
    public static func passages(of screen: ScreenRect, edge: ScreenEdge, others: [ScreenRect]) -> [EdgeSegment] {
        let full = edgeRange(screen, edge)
        var free = [EdgeSegment(start: full.start + cornerInset, end: full.end - cornerInset)]
        for other in others where other != screen {
            guard let blocked = contact(screen, edge, other) else { continue }
            free = free.flatMap { subtract(blocked, from: $0) }
        }
        return free.filter { $0.length >= minimumPassage }
    }

    /// 놓을 수 있는 가장 긴 통로. 없으면 nil.
    public static func longestPassage(of screen: ScreenRect, edge: ScreenEdge, others: [ScreenRect]) -> EdgeSegment? {
        passages(of: screen, edge: edge, others: others).max { $0.length < $1.length }
    }

    static func edgeRange(_ r: ScreenRect, _ edge: ScreenEdge) -> EdgeSegment {
        edge.isVertical ? EdgeSegment(start: r.y, end: r.maxY) : EdgeSegment(start: r.x, end: r.maxX)
    }

    /// `other`가 `screen`의 `edge`에 맞닿아 있으면 맞닿은 구간.
    static func contact(_ screen: ScreenRect, _ edge: ScreenEdge, _ other: ScreenRect) -> EdgeSegment? {
        let t = touchTolerance
        let touching: Bool
        switch edge {
        case .right: touching = abs(other.x - screen.maxX) <= t
        case .left: touching = abs(other.maxX - screen.x) <= t
        case .top: touching = abs(other.y - screen.maxY) <= t
        case .bottom: touching = abs(other.maxY - screen.y) <= t
        }
        guard touching else { return nil }
        let a = edgeRange(screen, edge), b = edgeRange(other, edge)
        let s = max(a.start, b.start), e = min(a.end, b.end)
        return e > s ? EdgeSegment(start: s, end: e) : nil
    }

    static func subtract(_ cut: EdgeSegment, from seg: EdgeSegment) -> [EdgeSegment] {
        guard cut.end > seg.start, cut.start < seg.end else { return [seg] }
        var out: [EdgeSegment] = []
        if cut.start > seg.start { out.append(EdgeSegment(start: seg.start, end: cut.start)) }
        if cut.end < seg.end { out.append(EdgeSegment(start: cut.end, end: seg.end)) }
        return out
    }

    /// 넘어가기 기준(pt). 기준 = 60 + 감도 × 200. Dock·메뉴 막대와 같은 쪽이면 1.8배.
    public static func pushThreshold(sensitivity: Double, sharesDockOrMenuBar: Bool) -> Double {
        let base = 60 + min(max(sensitivity, 0), 1) * 200
        return sharesDockOrMenuBar ? base * 1.8 : base
    }
}
