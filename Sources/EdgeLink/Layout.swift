import AppKit
import EdgeLinkCore

/// 모니터 목록과 아이폰을 놓을 수 있는 자리.
struct ScreenInfo: Identifiable, Equatable {
    let id: String          // 모니터 UUID
    let name: String
    let frame: ScreenRect
    let isMain: Bool
}

struct Placement: Identifiable, Equatable {
    let screen: ScreenInfo
    let edge: ScreenEdge
    let passage: EdgeSegment
    var id: String { "\(screen.id)-\(edge.rawValue)" }
    var label: String { "\(screen.name) \(edge.label)" }
}

enum Layout {
    static func screens() -> [ScreenInfo] {
        let main = NSScreen.screens.first
        var seen = Set<String>()
        return NSScreen.screens.compactMap { s in
            guard let number = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            // 미러링 중인 화면은 하나로 본다
            let mirrored = CGDisplayMirrorsDisplay(number)
            if mirrored != kCGNullDirectDisplay { return nil }
            let uuid = displayUUID(number)
            guard seen.insert(uuid).inserted else { return nil }
            let f = s.frame
            return ScreenInfo(id: uuid, name: s.localizedName,
                              frame: ScreenRect(x: f.minX, y: f.minY, width: f.width, height: f.height),
                              isMain: s == main)
        }
    }

    static func displayUUID(_ id: CGDirectDisplayID) -> String {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return CFUUIDCreateString(nil, cf) as String
    }

    /// 모든 모니터의 모든 모서리 중 놓을 수 있는 자리. 메인 모니터 오른쪽이 먼저.
    static func placements(_ screens: [ScreenInfo] = screens()) -> [Placement] {
        let rects = screens.map(\.frame)
        let order: [ScreenEdge] = [.right, .left, .bottom, .top]
        var out: [Placement] = []
        for s in screens.sorted(by: { $0.isMain && !$1.isMain }) {
            for e in order {
                if let p = LayoutGeometry.longestPassage(of: s.frame, edge: e, others: rects) {
                    out.append(Placement(screen: s, edge: e, passage: p))
                }
            }
        }
        return out
    }

    /// 기본값: 메인 모니터 오른쪽 (없으면 놓을 수 있는 첫 자리)
    static func defaultPlacement(_ placements: [Placement]) -> Placement? {
        placements.first { $0.screen.isMain && $0.edge == .right } ?? placements.first
    }

    /// 저장한 자리를 찾는다. 모니터가 없으면 nil (임시로 다른 빈 모서리를 쓴다).
    static func find(_ layout: PhoneLayout?, in placements: [Placement]) -> Placement? {
        guard let layout else { return nil }
        return placements.first { $0.screen.id == layout.screenID && $0.edge == layout.edge }
    }

    // MARK: Dock · 메뉴 막대

    enum DockSide { case bottom, left, right }

    static var dockSide: DockSide {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation")
        switch orientation {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }

    /// 이 자리가 Dock 또는 메뉴 막대와 같은 쪽인지. 같으면 더 길게 밀어야 넘어간다.
    static func conflict(_ p: Placement) -> String? {
        if p.edge == .top { return "메뉴 막대와 같은 쪽이에요." }
        guard p.screen.isMain else { return nil }
        switch (dockSide, p.edge) {
        case (.bottom, .bottom), (.left, .left), (.right, .right): return "Dock과 같은 쪽이에요."
        default: return nil
        }
    }
}
