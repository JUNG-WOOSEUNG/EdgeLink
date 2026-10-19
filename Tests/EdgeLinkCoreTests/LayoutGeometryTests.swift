@testable import EdgeLinkCore
import Testing

@Suite("통로 계산")
struct LayoutGeometryTests {
    let mac = ScreenRect(x: 0, y: 0, width: 1512, height: 982)
    // 맥북 오른쪽에 붙은 외장 모니터 (위로 조금 올라감)
    let lg = ScreenRect(x: 1512, y: 200, width: 2560, height: 1440)

    @Test func singleScreenEdgeMinusCorners() {
        let p = LayoutGeometry.passages(of: mac, edge: .right, others: [])
        #expect(p == [EdgeSegment(start: 24, end: 958)])
    }

    @Test func touchingEdgeBlocked() {
        // 맥북 오른쪽은 y 200~982가 LG와 맞닿음 → 24~200만 남음
        let p = LayoutGeometry.passages(of: mac, edge: .right, others: [lg])
        #expect(p == [EdgeSegment(start: 24, end: 200)])
    }

    @Test func fullyBlockedEdgeHasNoPassage() {
        let side = ScreenRect(x: 1512, y: 0, width: 1512, height: 982)
        #expect(LayoutGeometry.passages(of: mac, edge: .right, others: [side]).isEmpty)
        #expect(LayoutGeometry.longestPassage(of: mac, edge: .right, others: [side]) == nil)
    }

    @Test func shortPassageRejected() {
        // 맞닿지 않은 부분이 24~70 (46pt)라 60pt보다 짧음
        let other = ScreenRect(x: 1512, y: 70, width: 1000, height: 2000)
        #expect(LayoutGeometry.passages(of: mac, edge: .right, others: [other]).isEmpty)
    }

    @Test func nonTouchingScreenIgnored() {
        let far = ScreenRect(x: 3000, y: 0, width: 1000, height: 1000)
        #expect(LayoutGeometry.passages(of: mac, edge: .right, others: [far]).count == 1)
    }

    @Test func middleContactSplitsInTwo() {
        let small = ScreenRect(x: 1512, y: 300, width: 800, height: 300)
        let p = LayoutGeometry.passages(of: mac, edge: .right, others: [small])
        #expect(p == [EdgeSegment(start: 24, end: 300), EdgeSegment(start: 600, end: 958)])
        #expect(LayoutGeometry.longestPassage(of: mac, edge: .right, others: [small]) == EdgeSegment(start: 600, end: 958))
    }

    @Test func bottomEdgeUsesX() {
        let below = ScreenRect(x: 500, y: -1080, width: 1920, height: 1080)
        #expect(LayoutGeometry.passages(of: mac, edge: .bottom, others: [below]) == [EdgeSegment(start: 24, end: 500)])
    }

    @Test func pushThreshold() {
        #expect(LayoutGeometry.pushThreshold(sensitivity: 0.5, sharesDockOrMenuBar: false) == 160)
        #expect(LayoutGeometry.pushThreshold(sensitivity: 0.5, sharesDockOrMenuBar: true) == 288)
        #expect(LayoutGeometry.pushThreshold(sensitivity: 2, sharesDockOrMenuBar: false) == 260)
    }
}
