import Foundation

/// 앱 ↔ 블루투스 도우미(edgelink-hid) 사이의 짧은 바이너리 메시지.
///
/// 한 메시지 = 길이(UInt32, 리틀 엔디언) + 본문. 본문 첫 바이트가 종류다.
/// 마우스 움직임처럼 초당 수백 개 오가는 것도 있어서 JSON 대신 고정 형식으로 쓴다 (움직임 1개 = 13바이트).
public enum HelperProtocol {
    /// 앱과 도우미가 서로 다른 빌드면 hello에서 알아챈다
    public static let version: UInt16 = 1
    /// 이보다 긴 메시지는 깨진 것으로 본다
    public static let maxFrame = 1 << 20

    /// 본문 앞에 길이를 붙인다
    public static func frame(_ body: [UInt8]) -> [UInt8] {
        var w = ByteWriter()
        w.u32(UInt32(body.count))
        return w.bytes + body
    }
}

/// 받은 바이트를 모았다가 메시지 단위로 잘라 준다. 한 스레드에서만 쓴다.
public struct HelperFrameDecoder {
    private var buffer: [UInt8] = []
    private var start = 0
    public private(set) var broken = false

    public init() {}

    /// 새로 받은 바이트를 넣고, 다 모인 메시지 본문들을 돌려준다
    public mutating func append(_ bytes: [UInt8]) -> [[UInt8]] {
        guard !broken else { return [] }
        buffer.append(contentsOf: bytes)
        var out: [[UInt8]] = []
        while buffer.count - start >= 4 {
            let n = Int(buffer[start]) | Int(buffer[start + 1]) << 8 | Int(buffer[start + 2]) << 16 | Int(buffer[start + 3]) << 24
            guard n <= HelperProtocol.maxFrame else { broken = true; buffer = []; start = 0; return out }
            guard buffer.count - start - 4 >= n else { break }
            out.append(Array(buffer[(start + 4)..<(start + 4 + n)]))
            start += 4 + n
        }
        // 앞쪽 다 쓴 부분은 가끔 한 번에 지운다 (메시지마다 지우면 복사가 많다)
        if start == buffer.count { buffer.removeAll(keepingCapacity: true); start = 0 }
        else if start > 64 * 1024 { buffer.removeFirst(start); start = 0 }
        return out
    }
}

// MARK: - 앱 → 도우미

public enum HelperCommand: Equatable {
    /// 도우미 메인 스레드가 살아 있는지 묻는다 → pong
    case ping(UInt32)
    case publish(name: String)
    case unpublish
    case listen
    case stopListening
    case connect(address: String)
    case disconnect
    case setDefaultAddress(String?)
    case setAutoReconnect(Bool)
    case cancelReconnect
    case resetReconnectPolicy
    /// 아이폰 쪽에서 연결해 올 때 받을지: 이 주소면 받고, acceptAll이면 누구든 받는다
    case setAcceptPolicy(address: String?, acceptAll: Bool)
    case keyboard(KeyboardReport)
    case keyboardSequence([KeyboardReport], gapMs: UInt16)
    case consumer(UInt16)
    case move(dx: Int32, dy: Int32)
    case scroll(wheel: Int32, pan: Int32)
    case buttons(UInt8)
    case click(button: UInt8, holdMs: UInt16)
    case emptyReports
    /// 앞에서 보낸 리포트가 다 나갈 때까지 기다렸다가 flushed로 답한다
    case flush(UInt32)
    case motionDiagnostics(UInt32)
    /// 끊고 정리한 뒤 끝낸다
    case shutdown

    private enum Tag: UInt8 {
        case ping = 1, publish, unpublish, listen, stopListening, connect, disconnect, setDefaultAddress,
             setAutoReconnect, cancelReconnect, resetReconnectPolicy, setAcceptPolicy
        case keyboard = 40, keyboardSequence, consumer, move, scroll, buttons, click, emptyReports, flush, motionDiagnostics
        case shutdown = 90
    }

    public func encode() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case .ping(let s): w.u8(Tag.ping.rawValue); w.u32(s)
        case .publish(let name): w.u8(Tag.publish.rawValue); w.string(name)
        case .unpublish: w.u8(Tag.unpublish.rawValue)
        case .listen: w.u8(Tag.listen.rawValue)
        case .stopListening: w.u8(Tag.stopListening.rawValue)
        case .connect(let a): w.u8(Tag.connect.rawValue); w.string(a)
        case .disconnect: w.u8(Tag.disconnect.rawValue)
        case .setDefaultAddress(let a): w.u8(Tag.setDefaultAddress.rawValue); w.optionalString(a)
        case .setAutoReconnect(let on): w.u8(Tag.setAutoReconnect.rawValue); w.bool(on)
        case .cancelReconnect: w.u8(Tag.cancelReconnect.rawValue)
        case .resetReconnectPolicy: w.u8(Tag.resetReconnectPolicy.rawValue)
        case let .setAcceptPolicy(a, all): w.u8(Tag.setAcceptPolicy.rawValue); w.optionalString(a); w.bool(all)
        case .keyboard(let r): w.u8(Tag.keyboard.rawValue); w.keyboard(r)
        case let .keyboardSequence(rs, gap):
            w.u8(Tag.keyboardSequence.rawValue); w.u16(gap); w.u16(UInt16(min(rs.count, Int(UInt16.max))))
            rs.prefix(Int(UInt16.max)).forEach { w.keyboard($0) }
        case .consumer(let u): w.u8(Tag.consumer.rawValue); w.u16(u)
        case let .move(dx, dy): w.u8(Tag.move.rawValue); w.i32(dx); w.i32(dy)
        case let .scroll(wheel, pan): w.u8(Tag.scroll.rawValue); w.i32(wheel); w.i32(pan)
        case .buttons(let b): w.u8(Tag.buttons.rawValue); w.u8(b)
        case let .click(b, hold): w.u8(Tag.click.rawValue); w.u8(b); w.u16(hold)
        case .emptyReports: w.u8(Tag.emptyReports.rawValue)
        case .flush(let s): w.u8(Tag.flush.rawValue); w.u32(s)
        case .motionDiagnostics(let s): w.u8(Tag.motionDiagnostics.rawValue); w.u32(s)
        case .shutdown: w.u8(Tag.shutdown.rawValue)
        }
        return w.bytes
    }

    /// 모르는 종류거나 길이가 맞지 않으면 nil
    public static func decode(_ body: [UInt8]) -> HelperCommand? {
        var r = ByteReader(body)
        guard let raw = r.u8(), let tag = Tag(rawValue: raw) else { return nil }
        let cmd: HelperCommand?
        switch tag {
        case .ping: cmd = r.u32().map { .ping($0) }
        case .publish: cmd = r.string().map { .publish(name: $0) }
        case .unpublish: cmd = .unpublish
        case .listen: cmd = .listen
        case .stopListening: cmd = .stopListening
        case .connect: cmd = r.string().map { .connect(address: $0) }
        case .disconnect: cmd = .disconnect
        case .setDefaultAddress: cmd = r.optionalString().map { .setDefaultAddress($0) }
        case .setAutoReconnect: cmd = r.bool().map { .setAutoReconnect($0) }
        case .cancelReconnect: cmd = .cancelReconnect
        case .resetReconnectPolicy: cmd = .resetReconnectPolicy
        case .setAcceptPolicy:
            guard let a = r.optionalString(), let all = r.bool() else { return nil }
            cmd = .setAcceptPolicy(address: a, acceptAll: all)
        case .keyboard: cmd = r.keyboard().map { .keyboard($0) }
        case .keyboardSequence:
            guard let gap = r.u16(), let n = r.u16() else { return nil }
            var rs: [KeyboardReport] = []
            for _ in 0..<n { guard let k = r.keyboard() else { return nil }; rs.append(k) }
            cmd = .keyboardSequence(rs, gapMs: gap)
        case .consumer: cmd = r.u16().map { .consumer($0) }
        case .move:
            guard let dx = r.i32(), let dy = r.i32() else { return nil }
            cmd = .move(dx: dx, dy: dy)
        case .scroll:
            guard let w = r.i32(), let p = r.i32() else { return nil }
            cmd = .scroll(wheel: w, pan: p)
        case .buttons: cmd = r.u8().map { .buttons($0) }
        case .click:
            guard let b = r.u8(), let h = r.u16() else { return nil }
            cmd = .click(button: b, holdMs: h)
        case .emptyReports: cmd = .emptyReports
        case .flush: cmd = r.u32().map { .flush($0) }
        case .motionDiagnostics: cmd = r.u32().map { .motionDiagnostics($0) }
        case .shutdown: cmd = .shutdown
        }
        return r.atEnd ? cmd : nil
    }
}

// MARK: - 도우미 → 앱

/// 움직임 전송 진단 (BluetoothHID.takeMotionDiagnostics와 같은 내용)
public struct MotionDiagnostics: Equatable {
    public let sends: GapMeter.Summary
    public let maxSplit: Int
    public let maxWriteMs: Double

    public init(sends: GapMeter.Summary, maxSplit: Int, maxWriteMs: Double) {
        self.sends = sends
        self.maxSplit = maxSplit
        self.maxWriteMs = maxWriteMs
    }
}

public enum HelperEvent: Equatable {
    /// 도우미가 뜨자마자 한 번
    case hello(pid: Int32, version: UInt16)
    /// 도우미 메인 스레드에서 1초마다. 끊기면 앱이 도우미가 멈췄다고 본다
    case heartbeat
    case pong(UInt32)
    case state(BluetoothHID.State)
    /// 다음 자동 재연결까지 남은 초 (nil = 예약 없음)
    case reconnectScheduled(seconds: Double?)
    /// 허용하지 않은 기기가 연결해 와서 닫았다. 앱이 확인 창을 띄울지 정한다
    case incomingRejected(address: String, name: String)
    case leds(UInt8)
    /// 쓰기가 3번 연속 50ms를 넘었다
    case stalled
    /// 한 번 연결됐던 기기가 채널을 계속 거절한다. 도우미를 새로 띄워야 풀린다
    case needsFreshProcess
    case failure(String)
    case log(level: HIDLog.Level, message: String)
    case flushed(UInt32, ok: Bool)
    case motionDiagnostics(UInt32, MotionDiagnostics?)

    private enum Tag: UInt8 {
        case hello = 1, heartbeat, pong, state, reconnectScheduled, incomingRejected, leds, stalled, needsFreshProcess,
             failure, log, flushed, motionDiagnostics
    }

    public func encode() -> [UInt8] {
        var w = ByteWriter()
        switch self {
        case let .hello(pid, v): w.u8(Tag.hello.rawValue); w.i32(pid); w.u16(v)
        case .heartbeat: w.u8(Tag.heartbeat.rawValue)
        case .pong(let s): w.u8(Tag.pong.rawValue); w.u32(s)
        case .state(let s): w.u8(Tag.state.rawValue); w.state(s)
        case .reconnectScheduled(let s):
            w.u8(Tag.reconnectScheduled.rawValue); w.bool(s != nil); w.f64(s ?? 0)
        case let .incomingRejected(a, n): w.u8(Tag.incomingRejected.rawValue); w.string(a); w.string(n)
        case .leds(let l): w.u8(Tag.leds.rawValue); w.u8(l)
        case .stalled: w.u8(Tag.stalled.rawValue)
        case .needsFreshProcess: w.u8(Tag.needsFreshProcess.rawValue)
        case .failure(let m): w.u8(Tag.failure.rawValue); w.string(m)
        case let .log(level, message): w.u8(Tag.log.rawValue); w.u8(level.code); w.string(message)
        case let .flushed(s, ok): w.u8(Tag.flushed.rawValue); w.u32(s); w.bool(ok)
        case let .motionDiagnostics(s, d):
            w.u8(Tag.motionDiagnostics.rawValue); w.u32(s); w.bool(d != nil)
            if let d {
                w.u32(UInt32(clamping: d.sends.count)); w.f64(d.sends.averageMs); w.f64(d.sends.maxMs)
                w.u32(UInt32(clamping: d.sends.longGaps)); w.u32(UInt32(clamping: d.maxSplit)); w.f64(d.maxWriteMs)
            }
        }
        return w.bytes
    }

    public static func decode(_ body: [UInt8]) -> HelperEvent? {
        var r = ByteReader(body)
        guard let raw = r.u8(), let tag = Tag(rawValue: raw) else { return nil }
        let ev: HelperEvent?
        switch tag {
        case .hello:
            guard let pid = r.i32(), let v = r.u16() else { return nil }
            ev = .hello(pid: pid, version: v)
        case .heartbeat: ev = .heartbeat
        case .pong: ev = r.u32().map { .pong($0) }
        case .state: ev = r.state().map { .state($0) }
        case .reconnectScheduled:
            guard let has = r.bool(), let s = r.f64() else { return nil }
            ev = .reconnectScheduled(seconds: has ? s : nil)
        case .incomingRejected:
            guard let a = r.string(), let n = r.string() else { return nil }
            ev = .incomingRejected(address: a, name: n)
        case .leds: ev = r.u8().map { .leds($0) }
        case .stalled: ev = .stalled
        case .needsFreshProcess: ev = .needsFreshProcess
        case .failure: ev = r.string().map { .failure($0) }
        case .log:
            guard let c = r.u8(), let level = HIDLog.Level(code: c), let m = r.string() else { return nil }
            ev = .log(level: level, message: m)
        case .flushed:
            guard let s = r.u32(), let ok = r.bool() else { return nil }
            ev = .flushed(s, ok: ok)
        case .motionDiagnostics:
            guard let s = r.u32(), let has = r.bool() else { return nil }
            if !has { ev = .motionDiagnostics(s, nil); break }
            guard let count = r.u32(), let avg = r.f64(), let mx = r.f64(), let long = r.u32(),
                  let split = r.u32(), let write = r.f64() else { return nil }
            let summary = GapMeter.Summary(count: Int(count), averageMs: avg, maxMs: mx, longGaps: Int(long))
            ev = .motionDiagnostics(s, MotionDiagnostics(sends: summary, maxSplit: Int(split), maxWriteMs: write))
        }
        return r.atEnd ? ev : nil
    }
}

extension HIDLog.Level {
    var code: UInt8 {
        switch self { case .info: return 0; case .warn: return 1; case .error: return 2; case .debug: return 3 }
    }
    init?(code: UInt8) {
        switch code { case 0: self = .info; case 1: self = .warn; case 2: self = .error; case 3: self = .debug; default: return nil }
    }
}

// MARK: - 바이트 읽기·쓰기

struct ByteWriter {
    private(set) var bytes: [UInt8] = []
    /// 문자열은 이 길이(UTF-8 바이트)에서 자른다. 로그 한 줄이 너무 길어도 메시지 하나가 커지지 않게
    static let maxString = 8 * 1024

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func bool(_ v: Bool) { bytes.append(v ? 1 : 0) }
    mutating func u16(_ v: UInt16) { bytes.append(UInt8(v & 0xFF)); bytes.append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func f64(_ v: Double) {
        let b = v.bitPattern
        for i in 0..<8 { bytes.append(UInt8((b >> (8 * UInt64(i))) & 0xFF)) }
    }
    mutating func string(_ s: String) {
        var utf8 = Array(s.utf8)
        if utf8.count > Self.maxString {
            // 글자 중간에서 자르지 않게 앞으로 물러난다 (UTF-8 이어지는 바이트는 10xxxxxx)
            var n = Self.maxString
            while n > 0, utf8[n] & 0xC0 == 0x80 { n -= 1 }
            utf8 = Array(utf8[..<n])
        }
        u16(UInt16(utf8.count)); bytes.append(contentsOf: utf8)
    }
    mutating func optionalString(_ s: String?) { bool(s != nil); string(s ?? "") }
    mutating func keyboard(_ r: KeyboardReport) {
        u8(r.modifiers); u8(UInt8(min(r.keys.count, 6))); bytes.append(contentsOf: r.keys.prefix(6))
    }
    mutating func state(_ s: BluetoothHID.State) {
        switch s {
        case .idle: u8(0)
        case .connecting(let a): u8(1); string(a)
        case .connected(let a): u8(2); string(a)
        case .disconnected(let reason):
            u8(3)
            switch reason {
            case .user: u8(0)
            case .channelClosed: u8(1)
            case .virtualCableUnplug: u8(2)
            case .rejected: u8(3)
            case .stalled: u8(4)
            case let .openFailed(stage, code): u8(5); string(stage); i32(code)
            case .helperLost: u8(6)
            }
        }
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private var at = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { at == bytes.count }

    private mutating func take(_ n: Int) -> ArraySlice<UInt8>? {
        guard n >= 0, bytes.count - at >= n else { return nil }
        defer { at += n }
        return bytes[at..<(at + n)]
    }
    mutating func u8() -> UInt8? { take(1)?.first }
    mutating func bool() -> Bool? {
        guard let v = u8(), v <= 1 else { return nil }
        return v == 1
    }
    mutating func u16() -> UInt16? {
        guard let s = take(2) else { return nil }
        return UInt16(s[s.startIndex]) | UInt16(s[s.startIndex + 1]) << 8
    }
    mutating func u32() -> UInt32? {
        guard let s = take(4) else { return nil }
        return s.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }
    mutating func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }
    mutating func f64() -> Double? {
        guard let s = take(8) else { return nil }
        let bits = s.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        return Double(bitPattern: bits)
    }
    mutating func string() -> String? {
        guard let n = u16(), let s = take(Int(n)) else { return nil }
        return String(decoding: s, as: UTF8.self)
    }
    mutating func optionalString() -> String?? {
        guard let has = bool(), let s = string() else { return nil }
        return .some(has ? s : nil)
    }
    mutating func keyboard() -> KeyboardReport? {
        guard let m = u8(), let n = u8(), n <= 6, let keys = take(Int(n)) else { return nil }
        return KeyboardReport(modifiers: m, keys: Array(keys))
    }
    mutating func state() -> BluetoothHID.State? {
        guard let t = u8() else { return nil }
        switch t {
        case 0: return .idle
        case 1: return string().map { .connecting(address: $0) }
        case 2: return string().map { .connected(address: $0) }
        case 3:
            guard let r = u8() else { return nil }
            switch r {
            case 0: return .disconnected(.user)
            case 1: return .disconnected(.channelClosed)
            case 2: return .disconnected(.virtualCableUnplug)
            case 3: return .disconnected(.rejected)
            case 4: return .disconnected(.stalled)
            case 5:
                guard let stage = string(), let code = i32() else { return nil }
                return .disconnected(.openFailed(stage: stage, code: code))
            case 6: return .disconnected(.helperLost)
            default: return nil
            }
        default: return nil
        }
    }
}
