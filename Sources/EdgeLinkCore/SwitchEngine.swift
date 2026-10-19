import Foundation

// 전환(넘어가기·돌아오기)의 순수 계산. AppKit 없이 테스트할 수 있게 숫자만 다룬다.
// 수치는 설계 문서 › 핵심 동작, 화면 구성 › 모서리 효과 수치를 따른다.
//
// 좌표 약속
// - Mac 화면: Cocoa 기준(아래쪽이 y 0), 단위 pt. 이동량 dy는 위쪽이 +.
// - 아이폰: HID 단위, 왼쪽 위가 (0, 0), y는 아래쪽이 + (마우스 리포트와 같음).

// MARK: - 좌표 변환

public enum ScreenCoordinates {
    /// Quartz(CGEvent, 위쪽이 y 0) → Cocoa(아래쪽이 y 0). 기준은 메인 모니터 높이.
    public static func cocoaY(quartzY: Double, mainHeight: Double) -> Double { mainHeight - quartzY }
    /// Cocoa → Quartz. 같은 식이라 왕복하면 제자리.
    public static func quartzY(cocoaY: Double, mainHeight: Double) -> Double { mainHeight - cocoaY }
}

public extension ScreenEdge {
    /// 이 모서리에서 화면 밖으로 미는 양. dx·dy는 Cocoa 기준(위쪽 +).
    func outward(dx: Double, dy: Double) -> Double {
        switch self {
        case .right: return dx
        case .left: return -dx
        case .top: return dy
        case .bottom: return -dy
        }
    }
}

public extension EdgeSegment {
    func contains(_ v: Double) -> Bool { v >= start && v <= end }
    func clamp(_ v: Double) -> Double { min(max(v, start), end) }
}

// MARK: - 넘어가기 (통로 밀기)

/// 커서가 통로에 닿은 채 바깥으로 민 양을 모은다. 통로를 벗어나면 0.
public struct EdgePush {
    public struct Config: Equatable {
        public var screen: ScreenRect
        public var edge: ScreenEdge
        public var passage: EdgeSegment
        /// 넘어가기 기준(pt). `LayoutGeometry.pushThreshold`로 만든다.
        public var threshold: Double
        /// 드래그 중 전환 막기
        public var dragLock: Bool

        public init(screen: ScreenRect, edge: ScreenEdge, passage: EdgeSegment, threshold: Double, dragLock: Bool) {
            self.screen = screen; self.edge = edge; self.passage = passage
            self.threshold = threshold; self.dragLock = dragLock
        }
    }

    public enum Result: Equatable {
        /// 통로 밖이거나 밀지 않음
        case none
        /// 미는 중. progress 0~1, along은 모서리 방향 위치(pt)
        case pushing(progress: Double, along: Double)
        /// 기준을 넘음. fraction은 통로 안 비율(0 = 통로 시작점)
        case crossed(along: Double, fraction: Double)
        /// 버튼을 누른 채라 막음 (드래그 중 전환 막기)
        case blockedByDrag
    }

    /// 커서가 모서리 선에서 이만큼 안이면 닿았다고 본다 (Quartz ↔ Cocoa 변환으로 1pt 어긋남).
    public static let edgeTolerance: Double = 2
    /// 이 시간 동안 밀지 않으면 모은 양을 버린다 (효과가 사라지는 0.25 + 0.25초와 맞춤).
    public static let idleReset: TimeInterval = 0.5

    public var config: Config
    public private(set) var accumulated: Double = 0
    private var lastPush: TimeInterval?

    public init(config: Config) { self.config = config }

    public mutating func reset() {
        accumulated = 0
        lastPush = nil
    }

    /// 커서가 모서리에 닿아 있으면 모서리 방향 위치. 아니면 nil.
    public static func along(screen: ScreenRect, edge: ScreenEdge, x: Double, y: Double,
                             tolerance: Double = edgeTolerance) -> Double? {
        let t = tolerance
        switch edge {
        case .right:
            guard x >= screen.maxX - t, x <= screen.maxX + t, y >= screen.y - t, y <= screen.maxY + t else { return nil }
            return y
        case .left:
            guard x >= screen.x - t, x <= screen.x + t, y >= screen.y - t, y <= screen.maxY + t else { return nil }
            return y
        case .top:
            guard y >= screen.maxY - t, y <= screen.maxY + t, x >= screen.x - t, x <= screen.maxX + t else { return nil }
            return x
        case .bottom:
            guard y >= screen.y - t, y <= screen.y + t, x >= screen.x - t, x <= screen.maxX + t else { return nil }
            return x
        }
    }

    /// 마우스 이동 하나를 반영한다. x·y는 이동 뒤 커서 위치, dx·dy는 이동량(Cocoa 기준).
    public mutating func update(x: Double, y: Double, dx: Double, dy: Double,
                                buttonsDown: Bool, time: TimeInterval) -> Result {
        let c = config
        guard let along = Self.along(screen: c.screen, edge: c.edge, x: x, y: y), c.passage.contains(along) else {
            reset()
            return .none
        }
        if buttonsDown && c.dragLock {
            reset()
            return .blockedByDrag
        }
        if let last = lastPush, time - last > Self.idleReset { accumulated = 0 }
        let out = c.edge.outward(dx: dx, dy: dy)
        if out > 0 {
            accumulated += out
            lastPush = time
        }
        if accumulated >= c.threshold {
            let fraction = c.passage.length > 0 ? (along - c.passage.start) / c.passage.length : 0.5
            reset()
            return .crossed(along: along, fraction: min(max(fraction, 0), 1))
        }
        guard accumulated > 0 else { return .none }
        return .pushing(progress: min(accumulated / max(c.threshold, 1), 1), along: along)
    }
}

// MARK: - 아이폰 화면과 위치 추정

/// 아이폰 화면 크기와 Mac 통로의 대응.
/// 아이폰의 모서리 방향 비율 0~1이 Mac 통로의 시작~끝에 그대로 대응한다 ("같은 비율 높이").
public struct PhoneSurface: Equatable {
    /// 아이폰 화면(pt), 세로/가로 방향을 반영한 값
    public var width: Double
    public var height: Double
    /// 보정값 = 아이폰 1pt당 HID 이동량
    public var unitsPerPoint: Double
    /// 아이폰이 붙은 Mac 모서리
    public var macEdge: ScreenEdge
    /// Mac 쪽 통로
    public var passage: EdgeSegment

    public init(width: Double, height: Double, unitsPerPoint: Double, macEdge: ScreenEdge, passage: EdgeSegment) {
        self.width = width; self.height = height
        self.unitsPerPoint = unitsPerPoint; self.macEdge = macEdge; self.passage = passage
    }

    /// 안쪽 거리 축 길이(HID 단위) = 화면 깊이 × 보정값
    public var depthUnits: Double { (macEdge.isVertical ? width : height) * unitsPerPoint }
    /// 모서리 방향 축 길이(HID 단위) = 화면 길이 × 보정값
    public var alongUnits: Double { (macEdge.isVertical ? height : width) * unitsPerPoint }

    /// Mac 통로 위 위치 → 아이폰 모서리 방향 비율 (아이폰 기준 위·왼쪽이 0).
    /// 세로 모서리는 Mac은 위쪽이 +, 아이폰은 아래쪽이 +라서 뒤집는다.
    public func phoneFraction(macAlong: Double) -> Double {
        let f = passage.length > 0 ? (passage.clamp(macAlong) - passage.start) / passage.length : 0.5
        return macEdge.isVertical ? 1 - f : f
    }

    /// 아이폰 모서리 방향 비율 → Mac 통로 위 위치
    public func macAlong(phoneFraction: Double) -> Double {
        let p = min(max(phoneFraction, 0), 1)
        let f = macEdge.isVertical ? 1 - p : p
        return passage.start + f * passage.length
    }

    /// (안쪽, 모서리 방향) 이동 → 아이폰 HID 이동 (dx, dy)
    public func hidDelta(depth: Double, along: Double) -> (dx: Double, dy: Double) {
        switch macEdge {
        case .right: return (depth, along)     // 아이폰 왼쪽으로 들어감
        case .left: return (-depth, along)     // 아이폰 오른쪽으로 들어감
        case .top: return (along, -depth)      // 아이폰 아래쪽으로 들어감
        case .bottom: return (along, depth)    // 아이폰 위쪽으로 들어감
        }
    }

    /// 아이폰 HID 이동 (dx, dy) → (안쪽, 모서리 방향) 이동
    public func axisDelta(dx: Double, dy: Double) -> (depth: Double, along: Double) {
        switch macEdge {
        case .right: return (dx, dy)
        case .left: return (-dx, dy)
        case .top: return (-dy, dx)
        case .bottom: return (dy, dx)
        }
    }
}

/// 아이폰 안의 포인터 위치를 Mac이 추정한다. 끝에 닿으면 값을 잘라서 오차가 저절로 맞춰진다.
public struct PhonePointer: Equatable {
    /// 안쪽 거리가 이보다 작아지면(진입 모서리 밖으로 90 단위 넘게 밀면) 돌아온다
    public static let returnDistance: Double = -90
    /// 돌아온 커서는 모서리에서 이만큼 안쪽에 놓는다
    public static let returnInset: Double = 24

    public let surface: PhoneSurface
    /// 진입 모서리에서 안쪽으로의 거리 0 ~ depthUnits
    public private(set) var depth: Double
    /// 모서리 방향 위치 0 ~ alongUnits (아이폰 기준 위·왼쪽이 0)
    public private(set) var along: Double
    /// 진입 모서리에 닿은 뒤 바깥으로 더 민 양 (0 이하)
    public private(set) var beyond: Double = 0

    public init(surface: PhoneSurface, phoneFraction: Double, depth: Double = 0) {
        self.surface = surface
        self.along = min(max(phoneFraction, 0), 1) * surface.alongUnits
        self.depth = min(max(depth, 0), surface.depthUnits)
    }

    /// 안쪽 거리. 진입 모서리 밖으로 밀면 음수가 된다.
    public var innerDistance: Double { depth + beyond }
    public var phoneFraction: Double { surface.alongUnits > 0 ? along / surface.alongUnits : 0.5 }
    /// 지금 높이에 해당하는 Mac 통로 위 위치
    public var macAlong: Double { surface.macAlong(phoneFraction: phoneFraction) }

    /// 아이폰에 보낸 이동(HID 단위)을 반영한다.
    public mutating func move(dx: Double, dy: Double) {
        let a = surface.axisDelta(dx: dx, dy: dy)
        if a.depth > 0 {
            // 안쪽으로 움직이면 아이폰 포인터는 바로 안으로 들어온다
            beyond = 0
            depth = min(depth + a.depth, surface.depthUnits)
        } else if a.depth < 0 {
            let next = depth + a.depth
            if next < 0 {
                beyond += next
                depth = 0
            } else {
                depth = next
            }
        }
        along = min(max(along + a.along, 0), surface.alongUnits)
    }

    /// 돌아오기 조건: 안쪽 거리 < −90 단위, 그 높이가 통로 안, 버튼을 누르고 있지 않음.
    public func shouldReturn(buttonsDown: Bool) -> Bool {
        innerDistance < Self.returnDistance && !buttonsDown && surface.passage.contains(macAlong)
    }

    /// 돌아온 커서 위치(Cocoa): 같은 비율 높이, 모서리에서 24pt 안쪽.
    public func returnPoint(screen: ScreenRect) -> (x: Double, y: Double) {
        let a = surface.passage.clamp(macAlong)
        let i = Self.returnInset
        switch surface.macEdge {
        case .right: return (screen.maxX - i, a)
        case .left: return (screen.x + i, a)
        case .top: return (a, screen.maxY - i)
        case .bottom: return (a, screen.y + i)
        }
    }
}

// MARK: - 넘어가는 순간의 이동 계획

public struct HIDMove: Equatable {
    public var dx: Int, dy: Int
    public init(dx: Int, dy: Int) { self.dx = dx; self.dy = dy }
}

/// 넘어가는 순간: 아이폰 포인터를 진입 모서리 끝(구석)으로 크게 보낸 뒤 같은 비율 위치로 옮긴다.
/// 한 항목이 8ms 한 번 분량이다.
public enum EntryPlan {
    /// 구석으로 미는 총량 (축마다 5000 단위 넘게)
    public static let cornerUnits = 5200
    public static let cornerTicks = 10
    /// 제자리로 갈 때 한 번에 움직이는 최대량 (포인터 가속을 줄이려고 작게)
    public static let stepUnits = 32
    /// 진입 모서리에서 이만큼 안쪽에 놓는다 (pt)
    public static let insetPoints: Double = 4

    /// 구석으로 보내는 부분만 (보정 도우미의 "왼쪽 위로 보내기"에도 쓴다)
    public static func cornerMoves(dx sx: Int, dy sy: Int) -> [HIDMove] {
        let per = cornerUnits / cornerTicks
        return Array(repeating: HIDMove(dx: sx * per, dy: sy * per), count: cornerTicks)
    }

    /// 진입 모서리의 구석 방향 (안쪽 0, 모서리 방향 0)
    public static func cornerSign(_ surface: PhoneSurface) -> (dx: Int, dy: Int) {
        let d = surface.hidDelta(depth: -1, along: -1)
        return (d.dx < 0 ? -1 : 1, d.dy < 0 ? -1 : 1)
    }

    public static func moves(surface: PhoneSurface, phoneFraction: Double, stepUnits: Int = stepUnits) -> [HIDMove] {
        let s = cornerSign(surface)
        var out = cornerMoves(dx: s.dx, dy: s.dy)
        let depthTotal = Int((insetPoints * surface.unitsPerPoint).rounded())
        let alongTotal = Int((min(max(phoneFraction, 0), 1) * surface.alongUnits).rounded())
        var leftDepth = depthTotal, leftAlong = alongTotal
        let step = max(stepUnits, 1)
        while leftDepth > 0 || leftAlong > 0 {
            let d = min(step, leftDepth), a = min(step, leftAlong)
            leftDepth -= d; leftAlong -= a
            let h = surface.hidDelta(depth: Double(d), along: Double(a))
            out.append(HIDMove(dx: Int(h.dx), dy: Int(h.dy)))
        }
        return out
    }

    /// 계획을 다 보낸 뒤의 위치 추정값
    public static func pointerAfter(surface: PhoneSurface, phoneFraction: Double) -> PhonePointer {
        let alongTotal = (min(max(phoneFraction, 0), 1) * surface.alongUnits).rounded()
        let f = surface.alongUnits > 0 ? alongTotal / surface.alongUnits : 0
        return PhonePointer(surface: surface, phoneFraction: f,
                            depth: (insetPoints * surface.unitsPerPoint).rounded())
    }
}

// MARK: - 보정

public enum Calibration {
    public static let minimumValid: Double = 0.2
    public static let range: ClosedRange<Double> = 0.6...4.0

    public enum Outcome: Equatable {
        case success(Double)
        case failure(String)
    }

    /// (가로 이동 ÷ 화면 너비 + 세로 이동 ÷ 화면 높이) ÷ 2. 0.2 미만은 실패, 0.6~4.0으로 제한.
    public static func compute(dx: Double, dy: Double, width: Double, height: Double) -> Outcome {
        guard width > 0, height > 0 else { return .failure("기기 화면 크기를 알 수 없어요") }
        let v = (dx / width + dy / height) / 2
        guard v.isFinite, v >= minimumValid else { return .failure("포인터가 거의 움직이지 않았어요") }
        return .success(min(max(v, range.lowerBound), range.upperBound))
    }
}

// MARK: - 단축키

/// 키코드 + ⌃⌥⇧⌘ 마스크. 나머지 비트(Caps Lock, 키패드, Fn 등)는 보지 않는다.
public struct KeyCombo: Equatable, Hashable {
    public static let control: UInt64 = 0x40000
    public static let option: UInt64 = 0x80000
    public static let shift: UInt64 = 0x20000
    public static let command: UInt64 = 0x100000
    public static let relevant: UInt64 = control | option | shift | command

    public var keyCode: UInt16
    public var modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.relevant
    }

    /// 수정키 없는 조합은 등록돼 있어도 맞추지 않는다 (일반 타이핑을 가로채지 않게).
    public func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        modifiers != 0 && keyCode == self.keyCode && (flags & Self.relevant) == modifiers
    }
}

// MARK: - 수정키 눌림 판별

public enum ModifierKeys {
    public static let capsLockKeyCode: UInt16 = 0x39
    public static let fnKeyCode: UInt16 = 0x3F
    public static let escapeKeyCode: UInt16 = 0x35
    static let secondaryFn: UInt64 = 0x800000

    /// (장치별 비트, 같은 종류의 다른 쪽 비트, 일반 비트)
    static let table: [UInt16: (device: UInt64, sibling: UInt64, generic: UInt64)] = [
        0x3B: (0x0001, 0x2000, KeyCombo.control),   // 왼쪽 ⌃
        0x3E: (0x2000, 0x0001, KeyCombo.control),   // 오른쪽 ⌃
        0x38: (0x0002, 0x0004, KeyCombo.shift),     // 왼쪽 ⇧
        0x3C: (0x0004, 0x0002, KeyCombo.shift),     // 오른쪽 ⇧
        0x37: (0x0008, 0x0010, KeyCombo.command),   // 왼쪽 ⌘
        0x36: (0x0010, 0x0008, KeyCombo.command),   // 오른쪽 ⌘
        0x3A: (0x0020, 0x0040, KeyCombo.option),    // 왼쪽 ⌥
        0x3D: (0x0040, 0x0020, KeyCombo.option),    // 오른쪽 ⌥
    ]

    /// flagsChanged 이벤트에서 그 수정키가 눌렸는지(true) 떼졌는지(false).
    /// Caps Lock은 눌림이 아니라 상태가 바뀌는 키라 nil. 수정키가 아니면 nil.
    public static func isPressed(keyCode: UInt16, flags: UInt64) -> Bool? {
        if keyCode == fnKeyCode { return flags & secondaryFn != 0 }
        guard let e = table[keyCode] else { return nil }
        if flags & e.device != 0 { return true }
        // 장치별 비트가 없는 이벤트(합성 이벤트 등)는 일반 비트로 판단
        if flags & e.sibling == 0 && flags & e.generic != 0 { return true }
        return false
    }
}

// MARK: - 넘어갈 때 눌려 있던 키

/// 넘어가는 순간 Mac에서 눌려 있던 키를 기억한다. 그 키의 뗌은 Mac에, 아이폰에는 새로 누른 키만.
public struct HeldKeyTracker: Equatable {
    public enum Route: Equatable { case mac, phone, drop }

    public private(set) var heldAtEntry: Set<UInt16> = []

    public init() {}

    public mutating func begin(held: Set<UInt16>) { heldAtEntry = held }
    public mutating func clear() { heldAtEntry = [] }

    /// 키 누름. 키 반복은 보내지 않는다 (아이폰이 알아서 반복).
    public mutating func keyDown(_ code: UInt16, isRepeat: Bool) -> Route {
        if isRepeat { return .drop }
        // 넘어가기 전부터 눌려 있던 키가 다시 눌렸다면 뗌을 놓친 것: 새 키로 본다
        heldAtEntry.remove(code)
        return .phone
    }

    public mutating func keyUp(_ code: UInt16) -> Route {
        heldAtEntry.remove(code) != nil ? .mac : .phone
    }

    /// 수정키 변화. pressed는 `ModifierKeys.isPressed` 결과.
    public mutating func modifier(_ code: UInt16, pressed: Bool) -> Route {
        guard heldAtEntry.contains(code) else { return .phone }
        heldAtEntry.remove(code)
        return pressed ? .phone : .mac
    }
}

// MARK: - 스크롤

/// 트랙패드 스크롤(픽셀)은 12pt마다 휠 1칸. 마우스 휠(줄 단위)은 1줄 = 1칸.
public struct ScrollConverter: Equatable {
    public static let pointsPerNotch: Double = 12

    public var invert: Bool
    public private(set) var restY: Double = 0
    public private(set) var restX: Double = 0

    public init(invert: Bool = false) { self.invert = invert }

    public mutating func reset() { restY = 0; restX = 0 }

    /// deltaY: 위로 스크롤이 +(CGEvent 축 1). deltaX: CGEvent 축 2(왼쪽이 +).
    /// 돌려주는 값: wheel(위가 +), pan(오른쪽이 +).
    public mutating func convert(deltaY: Double, deltaX: Double, continuous: Bool) -> (wheel: Int, pan: Int) {
        var wheel: Int, pan: Int
        if continuous {
            wheel = Self.take(deltaY, &restY)
            pan = -Self.take(deltaX, &restX)
        } else {
            wheel = Self.lines(deltaY)
            pan = -Self.lines(deltaX)
        }
        if invert { wheel = -wheel; pan = -pan }
        return (wheel, pan)
    }

    static func take(_ delta: Double, _ rest: inout Double) -> Int {
        // 방향이 바뀌면 남은 양을 버린다 (반대로 돌렸는데 한 칸 늦게 반응하지 않게)
        if delta != 0, rest != 0, (delta > 0) != (rest > 0) { rest = 0 }
        rest += delta
        let n = (rest / pointsPerNotch).rounded(.towardZero)
        rest -= n * pointsPerNotch
        return Int(n)
    }

    static func lines(_ delta: Double) -> Int {
        guard delta != 0 else { return 0 }
        let n = Int(delta.rounded(.towardZero))
        return n != 0 ? n : (delta > 0 ? 1 : -1)
    }
}

// MARK: - Caps Lock · 아이패드 단축키

public enum CapsLockRule {
    /// Caps Lock 한 번을 아이폰에 보낼 리포트로. 한/영이 켜져 있으면 ⌃Space, 아니면 Caps Lock.
    /// 마지막 리포트는 원래 눌려 있던 상태로 되돌린다.
    public static func reports(hangul: Bool, current: KeyboardReport) -> [KeyboardReport] {
        if hangul {
            let ctrl = HIDUsage.modifierBit(HIDUsage.leftControl)!
            return [KeyboardReport(modifiers: ctrl), KeyboardReport(modifiers: ctrl, keys: [HIDUsage.space]),
                    KeyboardReport(modifiers: ctrl), current]
        }
        let keys = current.keys.count < 6 ? current.keys + [HIDUsage.capsLock] : current.keys
        return [KeyboardReport(modifiers: current.modifiers, keys: keys), current]
    }
}

public enum PadShortcut {
    public static let home: UInt8 = 0x0B      // H
    public static let appSwitcher: UInt8 = 0x2B  // Tab

    /// ⌘ + 키 한 번. 다른 수정키는 잠깐 떼고 보내고, 끝나면 원래대로.
    public static func reports(usage: UInt8, restore: KeyboardReport) -> [KeyboardReport] {
        let cmd = HIDUsage.modifierBit(HIDUsage.leftGUI)!
        return [KeyboardReport(modifiers: cmd), KeyboardReport(modifiers: cmd, keys: [usage]),
                KeyboardReport(modifiers: cmd), restore]
    }
}

// MARK: - 미디어 키

/// system-defined 이벤트(종류 14, 하위 종류 8)의 data1을 읽는다.
public enum MediaKey {
    public struct Event: Equatable {
        public var keyType: Int
        public var down: Bool
        public var isRepeat: Bool
    }

    public static let subtype = 8

    public static func parse(data1: Int) -> Event {
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        return Event(keyType: keyType, down: state == 0x0A, isRepeat: flags & 0x1 != 0)
    }

    /// 밝기(2, 3)·키보드 조명(21~23)은 항상 Mac. 전원 키(6)도 Mac에 둔다.
    public static func isBrightness(_ keyType: Int) -> Bool {
        [2, 3, 6, 21, 22, 23].contains(keyType)
    }

    /// NX_KEYTYPE → Consumer 용도. 보내지 않는 키는 nil.
    public static func consumerUsage(_ keyType: Int) -> UInt16? {
        switch keyType {
        case 0: return ConsumerReport.volumeUp
        case 1: return ConsumerReport.volumeDown
        case 7: return ConsumerReport.mute
        case 16: return ConsumerReport.playPause
        case 17, 19: return ConsumerReport.nextTrack
        case 18, 20: return ConsumerReport.previousTrack
        default: return nil
        }
    }
}

// MARK: - 트랙패드 제스처

public enum TrackpadGesture: Equatable {
    case threeFingerUp, threeFingerDown, fourFingerDown, fourFingerPinch
}

/// 트랙패드 손가락 위치(0~1, 아래쪽이 y 0)로 제스처를 알아낸다. 손가락을 다 뗄 때까지 한 번만.
public struct GestureRecognizer: Equatable {
    public struct Touch: Equatable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// 손가락 중심이 이만큼(트랙패드 높이 비율) 움직이면 쓸기
    public static let swipeDistance: Double = 0.12
    /// 손가락 사이 거리가 처음의 이 비율 아래로 줄면 모으기
    public static let pinchRatio: Double = 0.7

    private var count = 0
    private var startCenter = Touch(x: 0, y: 0)
    private var startSpread: Double = 0
    public private(set) var fired = false

    public init() {}

    public mutating func reset() {
        count = 0
        fired = false
    }

    public mutating func update(_ touches: [Touch]) -> TrackpadGesture? {
        if touches.isEmpty {
            reset()
            return nil
        }
        guard touches.count >= 3 else {
            count = 0
            return nil
        }
        let c = Self.center(touches)
        let spread = Self.spread(touches, c)
        if touches.count != count {
            // 손가락 수가 바뀌면 그때부터 다시 잰다
            count = touches.count
            startCenter = c
            startSpread = spread
            return nil
        }
        guard !fired else { return nil }
        let dx = c.x - startCenter.x, dy = c.y - startCenter.y
        let vertical = abs(dy) > abs(dx)
        var result: TrackpadGesture?
        if count == 3 {
            if vertical && dy >= Self.swipeDistance { result = .threeFingerUp }
            if vertical && dy <= -Self.swipeDistance { result = .threeFingerDown }
        } else {
            if startSpread > 0, spread / startSpread <= Self.pinchRatio {
                result = .fourFingerPinch
            } else if vertical && dy <= -Self.swipeDistance {
                result = .fourFingerDown
            }
        }
        if result != nil { fired = true }
        return result
    }

    static func center(_ t: [Touch]) -> Touch {
        let n = Double(t.count)
        return Touch(x: t.reduce(0) { $0 + $1.x } / n, y: t.reduce(0) { $0 + $1.y } / n)
    }

    static func spread(_ t: [Touch], _ c: Touch) -> Double {
        t.reduce(0) { $0 + hypot($1.x - c.x, $1.y - c.y) } / Double(t.count)
    }
}

// MARK: - 모서리 효과 수치

public enum GlowPhase: Equatable {
    case push(progress: Double)
    case enter
    case docked
    case returning
    case gone
}

/// 알약 수치. thickness는 화면 안으로 튀어나온 두께(알약 너비의 절반), length는 모서리 방향 길이.
public struct GlowMetrics: Equatable {
    public var thickness: Double
    public var length: Double
    public var opacity: Double
    /// 이 상태로 바뀌는 데 걸리는 시간 (0이면 애니메이션 없이 따라감)
    public var duration: Double

    public init(thickness: Double, length: Double, opacity: Double, duration: Double) {
        self.thickness = thickness; self.length = length; self.opacity = opacity; self.duration = duration
    }

    /// ease-out 곡선 cubic-bezier(0.2, 0.8, 0.2, 1)
    public static let curve: (Double, Double, Double, Double) = (0.2, 0.8, 0.2, 1)
    /// 밀다가 멈추면 이만큼 기다렸다가
    public static let pauseDelay: Double = 0.25
    /// 이 시간 동안 사라진다
    public static let pauseFade: Double = 0.25
    /// 동작 줄이기: 크기는 그대로, 불투명도만 이 시간 동안
    public static let reducedMotionDuration: Double = 0.2

    public static func metrics(_ phase: GlowPhase, passageLength: Double, reduceMotion: Bool = false) -> GlowMetrics {
        var m: GlowMetrics
        switch phase {
        case .push(let raw):
            let p = min(max(raw, 0), 1)
            m = GlowMetrics(thickness: 4 + 22 * p, length: 70 + 110 * p, opacity: 0.25 + 0.75 * p, duration: 0)
        case .enter: m = GlowMetrics(thickness: 34, length: 220, opacity: 1, duration: 0.12)
        case .docked: m = GlowMetrics(thickness: 6, length: 110, opacity: 0.85, duration: 0.28)
        case .returning: m = GlowMetrics(thickness: 30, length: 200, opacity: 1, duration: 0.1)
        case .gone: m = GlowMetrics(thickness: 2, length: 60, opacity: 0, duration: 0.3)
        }
        if reduceMotion {
            m.thickness = 26
            m.length = 180
            if m.duration > 0 { m.duration = reducedMotionDuration }
        }
        // 알약 길이는 통로 길이를 넘지 않는다
        m.length = min(m.length, max(passageLength, 0))
        return m
    }

    /// 알약 중심: 커서 위치를 따라가되 통로 밖으로 나가지 않게.
    public static func center(along: Double, length: Double, passage: EdgeSegment) -> Double {
        let lo = passage.start + length / 2, hi = passage.end - length / 2
        guard lo <= hi else { return (passage.start + passage.end) / 2 }
        return min(max(along, lo), hi)
    }
}

// MARK: - 클립보드 타이핑

public enum ClipboardTyping {
    /// 12ms 간격 (리포트 하나마다)
    public static let interval: TimeInterval = 0.012

    public struct Plan: Equatable {
        public var reports: [KeyboardReport]
        public var sendable: Int
        public var skipped: Int
        /// i번째 리포트를 보내기 전 남은 글자 수
        public func remaining(after sent: Int) -> Int {
            max(0, sendable - sent / 2)
        }
    }

    /// 영문·숫자·기호만 누름·뗌 리포트로. 나머지는 빼고 센다.
    public static func plan(_ text: String) -> Plan {
        var reports: [KeyboardReport] = []
        var sendable = 0, skipped = 0
        for ch in text {
            if let r = HIDUsage.typingReports(for: ch) {
                reports += r
                sendable += 1
            } else {
                skipped += 1
            }
        }
        return Plan(reports: reports, sendable: sendable, skipped: skipped)
    }
}

// MARK: - 이동량 소수점 이월

/// 소수점 이동량을 모아 정수로 보낸다 (작은 움직임이 사라지지 않게).
public struct MotionRemainder: Equatable {
    public private(set) var x: Double = 0
    public private(set) var y: Double = 0
    public init() {}

    public mutating func take(dx: Double, dy: Double) -> (dx: Int, dy: Int) {
        x += dx; y += dy
        let ix = x.rounded(.towardZero), iy = y.rounded(.towardZero)
        x -= ix; y -= iy
        return (Int(ix), Int(iy))
    }

    public mutating func reset() { x = 0; y = 0 }
}
