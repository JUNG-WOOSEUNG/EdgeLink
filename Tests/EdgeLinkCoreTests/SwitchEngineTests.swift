@testable import EdgeLinkCore
import Testing

// 맥북 화면 1512×982, 오른쪽 모서리 통로 24~958 (단일 모니터)
private let mac = ScreenRect(x: 0, y: 0, width: 1512, height: 982)
private let passage = EdgeSegment(start: 24, end: 958)

private func pushConfig(edge: ScreenEdge = .right, threshold: Double = 160, dragLock: Bool = true,
                        passage p: EdgeSegment = passage) -> EdgePush.Config {
    EdgePush.Config(screen: mac, edge: edge, passage: p, threshold: threshold, dragLock: dragLock)
}

private func surface(_ edge: ScreenEdge = .right, k: Double = 2,
                     passage p: EdgeSegment = passage) -> PhoneSurface {
    PhoneSurface(width: 393, height: 852, unitsPerPoint: k, macEdge: edge, passage: p)
}

@Suite("넘어가기 · 통로 밀기")
struct EdgePushTests {
    @Test func accumulatesUntilThreshold() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        #expect(p.update(x: 1511, y: 500, dx: 40, dy: 0, buttonsDown: false, time: 0) == .pushing(progress: 0.4, along: 500))
        #expect(p.update(x: 1511, y: 500, dx: 40, dy: 0, buttonsDown: false, time: 0.01) == .pushing(progress: 0.8, along: 500))
        let r = p.update(x: 1511, y: 500, dx: 20, dy: 0, buttonsDown: false, time: 0.02)
        #expect(r == .crossed(along: 500, fraction: (500 - 24) / 934))
        // 넘어간 뒤에는 0부터 다시
        #expect(p.accumulated == 0)
    }

    @Test func exactlyThresholdCrosses() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        if case .crossed = p.update(x: 1511, y: 500, dx: 100, dy: 0, buttonsDown: false, time: 0) {} else {
            Issue.record("기준과 같으면 넘어가야 해요")
        }
    }

    @Test func justBelowThresholdDoesNotCross() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        #expect(p.update(x: 1511, y: 500, dx: 99.9, dy: 0, buttonsDown: false, time: 0) != .crossed(along: 500, fraction: (500 - 24) / 934))
        #expect(p.accumulated == 99.9)
    }

    @Test func leavingPassageResets() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        _ = p.update(x: 1511, y: 500, dx: 80, dy: 0, buttonsDown: false, time: 0)
        // 모서리에서 안쪽으로 떨어짐
        #expect(p.update(x: 1400, y: 500, dx: -111, dy: 0, buttonsDown: false, time: 0.01) == .none)
        #expect(p.accumulated == 0)
        // 다시 닿아도 처음부터
        #expect(p.update(x: 1511, y: 500, dx: 30, dy: 0, buttonsDown: false, time: 0.02) == .pushing(progress: 0.3, along: 500))
    }

    @Test func cornerInsetIsOutsidePassage() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        // 통로 시작점 24 바로 아래(핫 코너)는 모으지 않음
        #expect(p.update(x: 1511, y: 23.9, dx: 500, dy: 0, buttonsDown: false, time: 0) == .none)
        // 경계값 24는 통로 안
        #expect(p.update(x: 1511, y: 24, dx: 50, dy: 0, buttonsDown: false, time: 0) == .pushing(progress: 0.5, along: 24))
        // 반대쪽 경계 958도 통로 안, 958.1은 밖
        #expect(p.update(x: 1511, y: 958, dx: 10, dy: 0, buttonsDown: false, time: 0) == .pushing(progress: 0.6, along: 958))
        #expect(p.update(x: 1511, y: 958.1, dx: 10, dy: 0, buttonsDown: false, time: 0) == .none)
    }

    @Test func inwardMotionDoesNotAdd() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        _ = p.update(x: 1511, y: 500, dx: 50, dy: 0, buttonsDown: false, time: 0)
        // 모서리에 닿은 채 위아래로만 움직이면 그대로
        #expect(p.update(x: 1511, y: 520, dx: 0, dy: 20, buttonsDown: false, time: 0.01) == .pushing(progress: 0.5, along: 520))
        #expect(p.accumulated == 50)
    }

    @Test func dragLockBlocksAndResets() {
        var p = EdgePush(config: pushConfig(threshold: 100, dragLock: true))
        _ = p.update(x: 1511, y: 500, dx: 60, dy: 0, buttonsDown: false, time: 0)
        #expect(p.update(x: 1511, y: 500, dx: 60, dy: 0, buttonsDown: true, time: 0.01) == .blockedByDrag)
        #expect(p.accumulated == 0)
    }

    @Test func dragAllowedWhenLockOff() {
        var p = EdgePush(config: pushConfig(threshold: 100, dragLock: false))
        _ = p.update(x: 1511, y: 500, dx: 60, dy: 0, buttonsDown: true, time: 0)
        if case .crossed = p.update(x: 1511, y: 500, dx: 60, dy: 0, buttonsDown: true, time: 0.01) {} else {
            Issue.record("드래그 막기를 끄면 버튼을 누른 채 넘어가야 해요")
        }
    }

    @Test func pauseResetsAccumulation() {
        var p = EdgePush(config: pushConfig(threshold: 100))
        _ = p.update(x: 1511, y: 500, dx: 90, dy: 0, buttonsDown: false, time: 0)
        // 0.5초 넘게 쉬었다가 다시 밀면 처음부터
        #expect(p.update(x: 1511, y: 500, dx: 20, dy: 0, buttonsDown: false, time: 0.6) == .pushing(progress: 0.2, along: 500))
    }

    @Test func leftTopBottomEdgesUseOwnDirection() {
        var l = EdgePush(config: pushConfig(edge: .left, threshold: 100))
        #expect(l.update(x: 0, y: 500, dx: -50, dy: 0, buttonsDown: false, time: 0) == .pushing(progress: 0.5, along: 500))
        #expect(l.update(x: 0, y: 500, dx: 50, dy: 0, buttonsDown: false, time: 0) == .pushing(progress: 0.5, along: 500))

        let hp = EdgeSegment(start: 24, end: 1488)
        var t = EdgePush(config: pushConfig(edge: .top, threshold: 100, passage: hp))
        // Cocoa 기준 위쪽 모서리 = maxY, 밀면 dy가 +
        #expect(t.update(x: 700, y: 982, dx: 0, dy: 50, buttonsDown: false, time: 0) == .pushing(progress: 0.5, along: 700))

        var b = EdgePush(config: pushConfig(edge: .bottom, threshold: 100, passage: hp))
        #expect(b.update(x: 700, y: 1, dx: 0, dy: -50, buttonsDown: false, time: 0) == .pushing(progress: 0.5, along: 700))
    }

    @Test func edgeTouchTolerance() {
        #expect(EdgePush.along(screen: mac, edge: .right, x: 1510, y: 300) == 300)
        #expect(EdgePush.along(screen: mac, edge: .right, x: 1509.9, y: 300) == nil)
        // 다른 모니터 높이(화면 밖)는 닿지 않은 것
        #expect(EdgePush.along(screen: mac, edge: .right, x: 1511, y: 1000) == nil)
    }

    @Test func thresholdWithDockIs18Times() {
        // 감도 0.5 → 160pt, Dock·메뉴 막대 쪽이면 288pt
        #expect(LayoutGeometry.pushThreshold(sensitivity: 0.5, sharesDockOrMenuBar: false) == 160)
        #expect(LayoutGeometry.pushThreshold(sensitivity: 0.5, sharesDockOrMenuBar: true) == 288)
    }
}

@Suite("아이폰 위치 추정 · 돌아오기")
struct PhonePointerTests {
    @Test func surfaceAxes() {
        let s = surface(.right, k: 2)
        #expect(s.depthUnits == 786)
        #expect(s.alongUnits == 1704)
        let t = surface(.top, k: 2)
        #expect(t.depthUnits == 1704)
        #expect(t.alongUnits == 786)
    }

    @Test func fractionFlipsOnVerticalEdges() {
        let s = surface(.right)
        // Mac 통로 위쪽 끝(958) = 아이폰 위쪽(0)
        #expect(s.phoneFraction(macAlong: 958) == 0)
        #expect(s.phoneFraction(macAlong: 24) == 1)
        #expect(s.macAlong(phoneFraction: 0) == 958)
        // 가로 모서리는 그대로
        let t = surface(.bottom, passage: EdgeSegment(start: 100, end: 300))
        #expect(t.phoneFraction(macAlong: 150) == 0.25)
        #expect(t.macAlong(phoneFraction: 0.25) == 150)
    }

    @Test func roundTripFraction() {
        let s = surface(.left)
        for a in stride(from: 24.0, through: 958, by: 93.4) {
            #expect(abs(s.macAlong(phoneFraction: s.phoneFraction(macAlong: a)) - a) < 1e-9)
        }
    }

    @Test func clampsAtFarSide() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.5)
        p.move(dx: 5000, dy: 0)
        #expect(p.depth == 786)
        // 끝에 닿은 뒤 돌아오는 양은 잘린 값 기준 (오차 자동 보정)
        p.move(dx: -100, dy: 0)
        #expect(p.depth == 686)
    }

    @Test func clampsAlong() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.5)
        p.move(dx: 0, dy: -9999)
        #expect(p.along == 0)
        p.move(dx: 0, dy: 9999)
        #expect(p.along == 1704)
    }

    @Test func returnsBelowMinus90() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.5, depth: 10)
        p.move(dx: -100, dy: 0)    // 안쪽 거리 −90 정확히: 아직
        #expect(p.innerDistance == -90)
        #expect(!p.shouldReturn(buttonsDown: false))
        p.move(dx: -1, dy: 0)
        #expect(p.innerDistance == -91)
        #expect(p.shouldReturn(buttonsDown: false))
    }

    @Test func buttonHoldsReturn() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.5)
        p.move(dx: -200, dy: 0)
        #expect(!p.shouldReturn(buttonsDown: true))
        #expect(p.shouldReturn(buttonsDown: false))
    }

    @Test func inwardMotionCancelsOvershoot() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.5)
        p.move(dx: -80, dy: 0)
        #expect(p.innerDistance == -80)
        // 안쪽으로 움직이면 아이폰 포인터는 바로 들어온다
        p.move(dx: 5, dy: 0)
        #expect(p.innerDistance == 5)
        p.move(dx: -60, dy: 0)
        #expect(!p.shouldReturn(buttonsDown: false))
    }

    @Test func directionsPerEdge() {
        // 왼쪽 배치: 아이폰 오른쪽으로 들어가서, 오른쪽(+x)으로 밀어야 돌아옴
        var l = PhonePointer(surface: surface(.left), phoneFraction: 0.5)
        l.move(dx: 100, dy: 0)
        #expect(l.shouldReturn(buttonsDown: false))
        // 위 배치: 아이폰 아래쪽으로 들어가서, 아래(+y)로 밀어야 돌아옴
        var t = PhonePointer(surface: surface(.top, passage: EdgeSegment(start: 24, end: 1488)), phoneFraction: 0.5)
        t.move(dx: 0, dy: 100)
        #expect(t.shouldReturn(buttonsDown: false))
        // 아래 배치: 위(−y)로
        var b = PhonePointer(surface: surface(.bottom, passage: EdgeSegment(start: 24, end: 1488)), phoneFraction: 0.5)
        b.move(dx: 0, dy: -100)
        #expect(b.shouldReturn(buttonsDown: false))
    }

    @Test func returnPointSameRatio24Inside() {
        var p = PhonePointer(surface: surface(.right), phoneFraction: 0.25)
        p.move(dx: -100, dy: 0)
        let pt = p.returnPoint(screen: mac)
        #expect(pt.x == 1512 - 24)
        // 아이폰 위에서 25% = Mac 통로 위에서 25% (Cocoa라서 958에서 내려옴)
        #expect(abs(pt.y - (958 - 0.25 * 934)) < 1e-9)

        let b = PhonePointer(surface: surface(.bottom, passage: EdgeSegment(start: 100, end: 500)), phoneFraction: 0.5)
        let bp = b.returnPoint(screen: mac)
        #expect(bp.x == 300)
        #expect(bp.y == 24)
    }
}

@Suite("넘어가는 순간 이동 계획")
struct EntryPlanTests {
    @Test func cornerPushIsOver5000() {
        let moves = EntryPlan.moves(surface: surface(.right), phoneFraction: 0.5)
        let corner = moves.prefix(EntryPlan.cornerTicks)
        #expect(corner.reduce(0) { $0 + $1.dx } <= -5000)
        #expect(corner.reduce(0) { $0 + $1.dy } <= -5000)
    }

    @Test func cornerDirectionPerEdge() {
        #expect(EntryPlan.cornerSign(surface(.right)) == (dx: -1, dy: -1) as (dx: Int, dy: Int))
        #expect(EntryPlan.cornerSign(surface(.left)) == (dx: 1, dy: -1) as (dx: Int, dy: Int))
        #expect(EntryPlan.cornerSign(surface(.top)) == (dx: -1, dy: 1) as (dx: Int, dy: Int))
        #expect(EntryPlan.cornerSign(surface(.bottom)) == (dx: -1, dy: -1) as (dx: Int, dy: Int))
    }

    @Test func movesToSameRatio() {
        let s = surface(.right, k: 2)
        let moves = EntryPlan.moves(surface: s, phoneFraction: 0.25)
        let after = moves.dropFirst(EntryPlan.cornerTicks)
        // 모서리 방향 0.25 × 1704 = 426, 안쪽 4pt × 2 = 8
        #expect(after.reduce(0) { $0 + $1.dy } == 426)
        #expect(after.reduce(0) { $0 + $1.dx } == 8)
        #expect(after.allSatisfy { abs($0.dx) <= EntryPlan.stepUnits && abs($0.dy) <= EntryPlan.stepUnits })
        let p = EntryPlan.pointerAfter(surface: s, phoneFraction: 0.25)
        #expect(p.along == 426)
        #expect(p.depth == 8)
    }

    @Test func leftEdgeMovesInwardNegative() {
        let moves = EntryPlan.moves(surface: surface(.left, k: 2), phoneFraction: 0)
        let after = moves.dropFirst(EntryPlan.cornerTicks)
        #expect(after.reduce(0) { $0 + $1.dx } == -8)
        #expect(after.reduce(0) { $0 + $1.dy } == 0)
    }
}

@Suite("보정 계산")
struct CalibrationTests {
    @Test func averageOfBothAxes() {
        // 가로 786 ÷ 393 = 2, 세로 1704 ÷ 852 = 2
        #expect(Calibration.compute(dx: 786, dy: 1704, width: 393, height: 852) == .success(2))
        #expect(Calibration.compute(dx: 393, dy: 2556, width: 393, height: 852) == .success(2))
    }

    @Test func belowPoint2Fails() {
        if case .success = Calibration.compute(dx: 70, dy: 170, width: 393, height: 852) {
            Issue.record("0.2보다 작으면 실패")
        }
        // 경계값 0.2는 실패가 아니고, 범위 아래라 0.6으로 올림
        #expect(Calibration.compute(dx: 78.6, dy: 170.4, width: 393, height: 852) == .success(0.6))
    }

    @Test func clampedToRange() {
        #expect(Calibration.compute(dx: 393 * 10, dy: 852 * 10, width: 393, height: 852) == .success(4.0))
        #expect(Calibration.compute(dx: 393 * 0.3, dy: 852 * 0.3, width: 393, height: 852) == .success(0.6))
    }

    @Test func invalidSizeFails() {
        if case .success = Calibration.compute(dx: 100, dy: 100, width: 0, height: 852) {
            Issue.record("크기가 0이면 실패")
        }
    }
}

@Suite("단축키 · 수정키 · 눌린 키")
struct KeyTests {
    let toggle = KeyCombo(keyCode: 0x31, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)

    @Test func matchesExactModifiers() {
        let f = KeyCombo.control | KeyCombo.option | KeyCombo.command
        #expect(toggle.matches(keyCode: 0x31, flags: f))
        // Caps Lock(0x10000)·키패드(0x200000)·Fn(0x800000)·장치 비트는 무시
        #expect(toggle.matches(keyCode: 0x31, flags: f | 0x10000 | 0x200000 | 0x800000 | 0x0029))
        // ⇧이 더 있으면 다른 조합
        #expect(!toggle.matches(keyCode: 0x31, flags: f | KeyCombo.shift))
        #expect(!toggle.matches(keyCode: 0x31, flags: KeyCombo.control | KeyCombo.option))
        #expect(!toggle.matches(keyCode: 0x30, flags: f))
    }

    @Test func comboWithoutModifiersNeverMatches() {
        let bare = KeyCombo(keyCode: 0x00, modifiers: 0)
        #expect(!bare.matches(keyCode: 0x00, flags: 0))
    }

    @Test func modifierPressDetection() {
        // 왼쪽 ⌘ 누름: 일반 비트 + 장치 비트 0x08
        #expect(ModifierKeys.isPressed(keyCode: 0x37, flags: KeyCombo.command | 0x08) == true)
        #expect(ModifierKeys.isPressed(keyCode: 0x37, flags: 0) == false)
        // 오른쪽 ⌘을 누른 채 왼쪽 ⌘을 뗌 → 왼쪽은 뗌
        #expect(ModifierKeys.isPressed(keyCode: 0x37, flags: KeyCombo.command | 0x10) == false)
        // 장치 비트 없는 합성 이벤트
        #expect(ModifierKeys.isPressed(keyCode: 0x3B, flags: KeyCombo.control) == true)
        #expect(ModifierKeys.isPressed(keyCode: 0x3F, flags: 0x800000) == true)
        #expect(ModifierKeys.isPressed(keyCode: 0x39, flags: 0x10000) == nil)
        #expect(ModifierKeys.isPressed(keyCode: 0x00, flags: 0) == nil)
    }

    @Test func heldKeysReleaseOnMac() {
        var h = HeldKeyTracker()
        h.begin(held: [0x3B, 0x3A, 0x37, 0x00])
        // 넘어갈 때 눌려 있던 ⌃의 뗌은 Mac에
        #expect(h.modifier(0x3B, pressed: false) == .mac)
        // 한 번 뗀 뒤 다시 누르면 아이폰에
        #expect(h.modifier(0x3B, pressed: true) == .phone)
        #expect(h.keyUp(0x00) == .mac)
        #expect(h.keyUp(0x00) == .phone)
        // 반복은 보내지 않음
        #expect(h.keyDown(0x37, isRepeat: true) == .drop)
        #expect(h.keyDown(0x01, isRepeat: true) == .drop)
        #expect(h.keyDown(0x01, isRepeat: false) == .phone)
    }

    @Test func heldKeyPressedAgainBecomesPhoneKey() {
        var h = HeldKeyTracker()
        h.begin(held: [0x00])
        #expect(h.keyDown(0x00, isRepeat: false) == .phone)
        #expect(h.keyUp(0x00) == .phone)
    }
}

@Suite("스크롤 변환")
struct ScrollTests {
    @Test func twelvePointsPerNotch() {
        var s = ScrollConverter(pointsPerNotch: 12)
        #expect(s.convert(deltaY: 11, deltaX: 0, continuous: true).wheel == 0)
        #expect(s.convert(deltaY: 1, deltaX: 0, continuous: true).wheel == 1)
        #expect(s.restY == 0)
        #expect(s.convert(deltaY: 30, deltaX: 0, continuous: true).wheel == 2)
        #expect(s.restY == 6)
    }

    @Test func momentumKeepsVerticalDropsHorizontal() {
        var s = ScrollConverter(pointsPerNotch: 12)
        _ = s.convert(deltaY: 0, deltaX: -10, continuous: true)
        let r = s.convert(deltaY: 24, deltaX: -24, continuous: true, momentum: true)
        #expect(r.wheel == 2)
        #expect(r.pan == 0)
        #expect(s.restX == 0)
        #expect(s.convert(deltaY: 0, deltaX: -12, continuous: true).pan == 1)
    }

    @Test func directionChangeDropsRest() {
        var s = ScrollConverter(pointsPerNotch: 12)
        _ = s.convert(deltaY: 10, deltaX: 0, continuous: true)
        #expect(s.convert(deltaY: -12, deltaX: 0, continuous: true).wheel == -1)
    }

    @Test func invertAndPan() {
        var s = ScrollConverter(invert: true, pointsPerNotch: 12)
        #expect(s.convert(deltaY: 24, deltaX: 0, continuous: true).wheel == -2)
        var n = ScrollConverter(pointsPerNotch: 12)
        // 축 2는 왼쪽이 +, HID 가로 스크롤은 오른쪽이 +
        #expect(n.convert(deltaY: 0, deltaX: 24, continuous: true).pan == -2)
    }

    @Test func defaultIsSlowerThanBefore() {
        var s = ScrollConverter()
        #expect(s.pointsPerNotch == 40)
        // 예전(12pt)엔 3칸이던 36pt 스크롤이 이제 0칸, 40pt면 1칸
        #expect(s.convert(deltaY: 36, deltaX: 0, continuous: true).wheel == 0)
        #expect(s.convert(deltaY: 4, deltaX: 0, continuous: true).wheel == 1)
    }

    @Test func speedMapping() {
        #expect(ScrollConverter.pointsPerNotch(speed: 0) == 70)
        #expect(ScrollConverter.pointsPerNotch(speed: 0.5) == 40)
        #expect(ScrollConverter.pointsPerNotch(speed: 1) == 10)
        #expect(ScrollConverter.pointsPerNotch(speed: 5) == 10)
    }

    @Test func lineScrollOneNotchPerLine() {
        var s = ScrollConverter()
        #expect(s.convert(deltaY: 3, deltaX: 0, continuous: false).wheel == 3)
        #expect(s.convert(deltaY: -0.4, deltaX: 0, continuous: false).wheel == -1)
        #expect(s.convert(deltaY: 0, deltaX: 0, continuous: false) == (wheel: 0, pan: 0))
    }
}

@Suite("Caps Lock · 아이패드 단축키 · 미디어 키")
struct SpecialKeyTests {
    @Test func capsLockHangulSendsCtrlSpace() {
        let r = CapsLockRule.reports(hangul: true, current: KeyboardReport())
        #expect(r.contains(KeyboardReport(modifiers: 0x01, keys: [HIDUsage.space])))
        #expect(r.last == KeyboardReport())
    }

    @Test func capsLockPlainSendsCapsAndRestores() {
        let cur = KeyboardReport(modifiers: 0x02, keys: [0x04])
        let r = CapsLockRule.reports(hangul: false, current: cur)
        #expect(r == [KeyboardReport(modifiers: 0x02, keys: [0x04, HIDUsage.capsLock]), cur])
    }

    @Test func padShortcutDropsOtherModifiers() {
        let held = KeyboardReport(modifiers: 0x01 | 0x04 | 0x08) // ⌃⌥⌘ (대체 단축키를 누른 채)
        let r = PadShortcut.reports(usage: PadShortcut.home, restore: held)
        #expect(r[1] == KeyboardReport(modifiers: 0x08, keys: [0x0B]))
        #expect(r.last == held)
    }

    @Test func mediaKeyParse() {
        // 볼륨 업 누름: keyType 0, 상태 0x0A
        let down = MediaKey.parse(data1: (0 << 16) | (0x0A << 8))
        #expect(down == MediaKey.Event(keyType: 0, down: true, isRepeat: false))
        let up = MediaKey.parse(data1: (16 << 16) | (0x0B << 8))
        #expect(up.keyType == 16 && !up.down)
        let rep = MediaKey.parse(data1: (1 << 16) | (0x0A << 8) | 1)
        #expect(rep.isRepeat)
        #expect(MediaKey.consumerUsage(0) == ConsumerReport.volumeUp)
        #expect(MediaKey.consumerUsage(16) == ConsumerReport.playPause)
        // 밝기는 아이폰으로 보내지 않음
        #expect(MediaKey.isBrightness(2) && MediaKey.isBrightness(3))
        #expect(MediaKey.consumerUsage(2) == nil)
    }
}

@Suite("트랙패드 제스처 인식")
struct GestureTests {
    typealias T = GestureRecognizer.Touch
    func fingers(_ n: Int, y: Double, spread: Double = 0.1) -> [T] {
        (0..<n).map { T(x: 0.3 + Double($0) * spread, y: y) }
    }

    @Test func threeFingerUpOnce() {
        var g = GestureRecognizer()
        #expect(g.update(fingers(3, y: 0.3)) == nil)
        #expect(g.update(fingers(3, y: 0.38)) == nil)
        #expect(g.update(fingers(3, y: 0.43)) == .threeFingerUp)
        // 한 제스처에 한 번만
        #expect(g.update(fingers(3, y: 0.7)) == nil)
        // 손가락을 다 떼면 다시 인식
        #expect(g.update([]) == nil)
        #expect(g.update(fingers(3, y: 0.7)) == nil)
        #expect(g.update(fingers(3, y: 0.5)) == .threeFingerDown)
    }

    @Test func fourFingerDownAndPinch() {
        var g = GestureRecognizer()
        _ = g.update(fingers(4, y: 0.6))
        #expect(g.update(fingers(4, y: 0.45)) == .fourFingerDown)
        var p = GestureRecognizer()
        _ = p.update(fingers(4, y: 0.5, spread: 0.15))
        #expect(p.update(fingers(4, y: 0.5, spread: 0.1)) == .fourFingerPinch)
    }

    @Test func twoFingersIgnoredAndHorizontalIgnored() {
        var g = GestureRecognizer()
        _ = g.update(fingers(2, y: 0.2))
        #expect(g.update(fingers(2, y: 0.8)) == nil)
        var h = GestureRecognizer()
        _ = h.update(fingers(3, y: 0.5))
        // 가로로 크게 움직이면 위아래 쓸기로 보지 않음
        let moved = fingers(3, y: 0.65).map { T(x: $0.x + 0.3, y: $0.y) }
        #expect(h.update(moved) == nil)
    }
}

@Suite("모서리 효과 수치")
struct GlowTests {
    @Test func pushInterpolates() {
        #expect(GlowMetrics.metrics(.push(progress: 0), passageLength: 900) == GlowMetrics(thickness: 4, length: 70, opacity: 0.25, duration: 0))
        #expect(GlowMetrics.metrics(.push(progress: 1), passageLength: 900) == GlowMetrics(thickness: 26, length: 180, opacity: 1, duration: 0))
        let half = GlowMetrics.metrics(.push(progress: 0.5), passageLength: 900)
        #expect(half.thickness == 15 && half.length == 125 && half.opacity == 0.625)
        // 범위 밖 진행도는 잘라냄
        #expect(GlowMetrics.metrics(.push(progress: 3), passageLength: 900).thickness == 26)
    }

    @Test func phaseTable() {
        #expect(GlowMetrics.metrics(.enter, passageLength: 900) == GlowMetrics(thickness: 34, length: 220, opacity: 1, duration: 0.12))
        #expect(GlowMetrics.metrics(.docked, passageLength: 900) == GlowMetrics(thickness: 6, length: 110, opacity: 0.85, duration: 0.28))
        #expect(GlowMetrics.metrics(.returning, passageLength: 900) == GlowMetrics(thickness: 30, length: 200, opacity: 1, duration: 0.1))
        #expect(GlowMetrics.metrics(.gone, passageLength: 900).opacity == 0)
    }

    @Test func lengthNeverExceedsPassage() {
        #expect(GlowMetrics.metrics(.enter, passageLength: 100).length == 100)
    }

    @Test func reducedMotionKeepsSize() {
        let a = GlowMetrics.metrics(.enter, passageLength: 900, reduceMotion: true)
        let b = GlowMetrics.metrics(.docked, passageLength: 900, reduceMotion: true)
        #expect(a.thickness == b.thickness && a.length == b.length)
        #expect(a.duration == 0.2)
        #expect(b.opacity == 0.85)
    }

    @Test func centerStaysInPassage() {
        let p = EdgeSegment(start: 100, end: 500)
        #expect(GlowMetrics.center(along: 110, length: 180, passage: p) == 190)
        #expect(GlowMetrics.center(along: 300, length: 180, passage: p) == 300)
        #expect(GlowMetrics.center(along: 499, length: 180, passage: p) == 410)
        #expect(GlowMetrics.center(along: 0, length: 600, passage: p) == 300)
    }
}

@Suite("클립보드 · 이동 이월 · 좌표")
struct SwitchMiscTests {
    @Test func typingPlanSkipsNonASCII() {
        let plan = ClipboardTyping.plan("Hi 한글!")
        #expect(plan.sendable == 4)
        #expect(plan.skipped == 2)
        #expect(plan.reports.count == 8)
        #expect(plan.remaining(after: 0) == 4)
        #expect(plan.remaining(after: 3) == 3)
        #expect(plan.remaining(after: 8) == 0)
    }

    @Test func remainderCarriesFractions() {
        var m = MotionRemainder()
        #expect(m.take(dx: 0.6, dy: -0.6) == (dx: 0, dy: 0))
        #expect(m.take(dx: 0.6, dy: -0.6) == (dx: 1, dy: -1))
        #expect(abs(m.x - 0.2) < 1e-9)
    }

    @Test func quartzCocoaRoundTrip() {
        #expect(ScreenCoordinates.cocoaY(quartzY: 0, mainHeight: 982) == 982)
        #expect(ScreenCoordinates.quartzY(cocoaY: ScreenCoordinates.cocoaY(quartzY: 123, mainHeight: 982), mainHeight: 982) == 123)
    }
}

@Suite("단축키로 넘어갈 때 위치")
struct HotkeyEntryDepthTests {
    let s = PhoneSurface(width: 393, height: 852, unitsPerPoint: 2, macEdge: .right,
                         passage: EdgeSegment(start: 24, end: 958))

    @Test func centerDepthIsHalfScreen() {
        #expect(EntryPlan.centerDepthPoints(s) == 393.0 / 2)
    }

    @Test func pointerAfterCenterIsFarFromReturn() {
        var p = EntryPlan.pointerAfter(surface: s, phoneFraction: 0.5, depthPoints: EntryPlan.centerDepthPoints(s))
        let start = p.innerDistance
        #expect(start > 300)
        // Mac 쪽(돌아오는 방향)으로 200단위 움직여도 돌아오지 않는다
        p.move(dx: -100, dy: 0)
        p.move(dx: -100, dy: 0)
        #expect(p.innerDistance < start)
        #expect(!p.shouldReturn(buttonsDown: false))
    }

    @Test func edgeEntryStaysNearEdge() {
        let p = EntryPlan.pointerAfter(surface: s, phoneFraction: 0.5)
        #expect(p.innerDistance == 8)
    }
}

@Suite("포인터 속도")
struct PointerScaleTests {
    @Test func defaultMatchesMacDistance() {
        // 보정값 1.74, 속도 1.0 → Mac 1pt가 아이폰 1.74단위(=1pt)
        #expect(abs(PointerScale.scale(unitsPerPoint: 1.74, speed: 1.0) - 1.74) < 1e-9)
    }

    @Test func speedClampedAndBadCalibrationFallsBack() {
        #expect(PointerScale.scale(unitsPerPoint: 2, speed: 10) == 4)
        #expect(PointerScale.scale(unitsPerPoint: 2, speed: 0) == 1)
        #expect(PointerScale.scale(unitsPerPoint: .nan, speed: 1) == 2)
        #expect(PointerScale.scale(unitsPerPoint: 0, speed: 1) == 2)
    }
}
