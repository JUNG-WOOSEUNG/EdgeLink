@testable import EdgeLinkCore
import Foundation
import Testing

@Suite("도우미 메시지")
struct HelperMessagesTests {
    static let commands: [HelperCommand] = [
        .ping(7), .publish(name: "EdgeLink"), .unpublish, .listen, .stopListening,
        .connect(address: "00-11-22-33-44-55"), .disconnect,
        .setDefaultAddress("00-11-22-33-44-55"), .setDefaultAddress(nil),
        .setAutoReconnect(true), .setAutoReconnect(false), .cancelReconnect, .resetReconnectPolicy,
        .setAcceptPolicy(address: nil, acceptAll: true), .setAcceptPolicy(address: "00-11-22-33-44-55", acceptAll: false),
        .keyboard(KeyboardReport(modifiers: 0x01, keys: [0x2C])), .keyboard(KeyboardReport()),
        .keyboardSequence([KeyboardReport(modifiers: 1), KeyboardReport(modifiers: 1, keys: [0x2C]), KeyboardReport()], gapMs: 20),
        .consumer(0xE9), .move(dx: -300, dy: 2_000_000), .scroll(wheel: -3, pan: 1), .buttons(0x05),
        .click(button: 4, holdMs: 100), .emptyReports, .flush(UInt32.max), .motionDiagnostics(3), .shutdown,
    ]

    static let events: [HelperEvent] = [
        .hello(pid: 1234, version: HelperProtocol.version), .heartbeat, .pong(9),
        .state(.idle), .state(.connecting(address: "00-11-22-33-44-55")), .state(.connected(address: "00-11-22-33-44-55")),
        .state(.disconnected(.user)), .state(.disconnected(.channelClosed)), .state(.disconnected(.virtualCableUnplug)),
        .state(.disconnected(.rejected)), .state(.disconnected(.stalled)), .state(.disconnected(.helperLost)),
        .state(.disconnected(.openFailed(stage: "인터럽트 채널(0x13)", code: Int32(bitPattern: 0xE00002BC)))),
        .reconnectScheduled(seconds: 15), .reconnectScheduled(seconds: nil),
        .incomingRejected(address: "00-11-22-33-44-55", name: "지민의 iPhone"), .leds(0x02), .stalled, .needsFreshProcess,
        .failure("Mac 블루투스가 꺼져 있어요"), .log(level: .warn, message: "쓰기 지연 62ms"), .log(level: .debug, message: ""),
        .flushed(5, ok: true), .flushed(6, ok: false), .motionDiagnostics(1, nil),
        .motionDiagnostics(2, MotionDiagnostics(sends: GapMeter.Summary(count: 120, averageMs: 8.1, maxMs: 31.5, longGaps: 1),
                                                maxSplit: 3, maxWriteMs: 2.25)),
    ]

    @Test(arguments: commands) func commandRoundTrip(_ c: HelperCommand) {
        #expect(HelperCommand.decode(c.encode()) == c)
    }

    @Test(arguments: events) func eventRoundTrip(_ e: HelperEvent) {
        #expect(HelperEvent.decode(e.encode()) == e)
    }

    @Test func moveIsSmall() {
        // 마우스 움직임은 초당 수백 개라 짧아야 한다: 길이 4 + 종류 1 + dx·dy 8
        #expect(HelperProtocol.frame(HelperCommand.move(dx: 1, dy: -1).encode()).count == 13)
    }

    @Test func rejectsTruncatedAndTrailingBytes() {
        let body = HelperCommand.connect(address: "00-11-22-33-44-55").encode()
        #expect(HelperCommand.decode(Array(body.dropLast())) == nil)
        #expect(HelperCommand.decode(body + [0]) == nil)
        #expect(HelperCommand.decode([]) == nil)
        #expect(HelperCommand.decode([0xEE]) == nil)
        #expect(HelperEvent.decode([0xEE]) == nil)
        // bool은 0·1만
        #expect(HelperCommand.decode([HelperCommand.setAutoReconnect(true).encode()[0], 2]) == nil)
    }

    @Test func decoderSplitsFramesAcrossChunks() {
        let frames = [HelperCommand.ping(1), .move(dx: 3, dy: 4), .publish(name: "EdgeLink")]
        let stream = frames.flatMap { HelperProtocol.frame($0.encode()) }
        // 1바이트씩 넣어도, 한 번에 넣어도 같은 메시지가 나온다
        var one = HelperFrameDecoder()
        var got: [HelperCommand] = []
        for b in stream { got += one.append([b]).compactMap(HelperCommand.decode) }
        #expect(got == frames)
        var all = HelperFrameDecoder()
        #expect(all.append(stream).compactMap(HelperCommand.decode) == frames)
    }

    @Test func decoderStopsOnOversizedLength() {
        var d = HelperFrameDecoder()
        #expect(d.append([0xFF, 0xFF, 0xFF, 0x7F, 1, 2]).isEmpty)
        #expect(d.broken)
        #expect(d.append(HelperProtocol.frame([1])).isEmpty)
    }

    @Test func longStringsAreCutOnCharacterBoundary() {
        let long = String(repeating: "가", count: 5000)   // 15000바이트
        guard case let .log(_, m)? = HelperEvent.decode(HelperEvent.log(level: .info, message: long).encode()) else {
            Issue.record("디코드 실패"); return
        }
        #expect(m.utf8.count <= ByteWriter.maxString)
        #expect(m.allSatisfy { $0 == "가" })
    }
}
