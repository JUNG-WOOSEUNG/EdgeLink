@testable import EdgeLinkCore
import Foundation
import Testing

/// 가짜 도우미: 받은 명령을 모아 두고, ping·flush에는 바로 답한다.
private final class FakeLink: HelperLink {
    let pid: Int32
    let handlers: HelperLinkHandlers
    private let lock = NSLock()
    private var _sent: [HelperCommand] = []
    private(set) var terminated = false
    private(set) var closed = false

    init(pid: Int32, handlers: HelperLinkHandlers) {
        self.pid = pid
        self.handlers = handlers
    }

    var sent: [HelperCommand] { lock.lock(); defer { lock.unlock() }; return _sent }

    func send(_ frame: [UInt8]) -> Bool {
        var d = HelperFrameDecoder()
        guard let cmd = d.append(frame).first.flatMap(HelperCommand.decode) else { return false }
        lock.lock(); _sent.append(cmd); lock.unlock()
        switch cmd {
        case .ping(let s): handlers.onEvent(.pong(s))
        case .flush(let s): handlers.onEvent(.flushed(s, ok: true))
        default: break
        }
        return true
    }

    func close() { closed = true }
    func terminate() { terminated = true; handlers.onExit(15) }
    func waitForExit(timeout: TimeInterval) -> Bool { true }

    /// 도우미가 보낸 것처럼
    func emit(_ ev: HelperEvent) { handlers.onEvent(ev) }
    func exit(_ status: Int32) { handlers.onExit(status) }
}

private final class Recorder: HIDHelperClientDelegate {
    private let lock = NSLock()
    private var _states: [BluetoothHID.State] = []
    private var _stalls = 0
    private var _rejected: [String] = []
    var states: [BluetoothHID.State] { lock.lock(); defer { lock.unlock() }; return _states }
    var stalls: Int { lock.lock(); defer { lock.unlock() }; return _stalls }
    var rejected: [String] { lock.lock(); defer { lock.unlock() }; return _rejected }

    func hid(_ hid: HIDHelperClient, didChange state: BluetoothHID.State) { lock.lock(); _states.append(state); lock.unlock() }
    func hidTransportStalled(_ hid: HIDHelperClient) { lock.lock(); _stalls += 1; lock.unlock() }
    func hid(_ hid: HIDHelperClient, didRejectIncoming address: String, name: String) {
        lock.lock(); _rejected.append(address); lock.unlock()
    }
}

/// 가짜 도우미를 띄우는 시험대
private final class Bench {
    let queue = DispatchQueue(label: "test.hid.client")
    let client: HIDHelperClient
    let recorder = Recorder()
    private let lock = NSLock()
    private var _links: [FakeLink] = []
    var links: [FakeLink] { lock.lock(); defer { lock.unlock() }; return _links }

    init(timing: HIDHelperClient.Timing = Bench.fastTiming()) {
        var made: (HelperLinkHandlers) -> HelperLink = { _ in fatalError() }
        let client = HIDHelperClient(launcher: { made($0) }, queue: queue, timing: timing)
        self.client = client
        made = { [unowned self] handlers in
            let l = FakeLink(pid: Int32(100 + self.links.count), handlers: handlers)
            self.lock.lock(); self._links.append(l); self.lock.unlock()
            return l
        }
        client.bluetoothPoweredOn = { true }
        client.delegate = recorder
    }

    static func fastTiming() -> HIDHelperClient.Timing {
        var t = HIDHelperClient.Timing()
        t.heartbeatTimeout = 60
        t.silentStall = 60
        t.watchInterval = 0.02
        t.freshRestartDelay = 0.05
        t.restart = HelperRestartPolicy(delays: [0.05])
        return t
    }

    func onQueue<T>(_ work: () throws -> T) rethrows -> T { try queue.sync(execute: work) }
    var state: BluetoothHID.State { onQueue { client.state } }

    /// 조건이 맞을 때까지 기다린다 (큐의 남은 일도 처리되게)
    func wait(_ timeout: TimeInterval = 3, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            queue.sync {}
            if cond() { return true }
            usleep(10_000)
        }
        return cond()
    }
}

@Suite("도우미 대리 객체")
struct HIDHelperClientTests {
    private let address = "00-11-22-33-44-55"

    @Test func launchesLazilyAndReplaysSettings() throws {
        let b = Bench()
        b.onQueue {
            b.client.autoReconnect = true
            b.client.defaultAddress = address
            b.client.acceptPolicy = .init(address: address, acceptAll: false)
            b.client.sendEmptyReports()   // 도우미가 없으면 버린다 (띄우지 않음)
        }
        #expect(b.links.isEmpty)
        try b.onQueue { try b.client.publishServiceRecord(name: "EdgeLink") }
        b.onQueue { b.client.listen() }
        #expect(b.links.count == 1)
        let sent = b.links[0].sent
        #expect(Array(sent.prefix(4)) == [
            .setAutoReconnect(true), .setDefaultAddress(address), .setAcceptPolicy(address: address, acceptAll: false),
            .publish(name: "EdgeLink"),
        ])
        #expect(sent.contains(.listen))
    }

    @Test func reportsGoStraightThroughInOrder() {
        let b = Bench()
        b.onQueue { b.client.startHelper() }
        DispatchQueue.global().sync {   // 메인이 아닌 스레드에서 보내도 된다
            b.client.move(dx: 5, dy: -5)
            b.client.setButtons(1)
            b.client.send(KeyboardReport(keys: [0x04]))
            b.client.click(button: 4, hold: 0.1)
            b.client.send([KeyboardReport(modifiers: 1)], gap: 0.02)
        }
        let reports = b.links[0].sent.filter {
            switch $0 { case .move, .buttons, .keyboard, .click, .keyboardSequence: return true; default: return false }
        }
        #expect(reports == [.move(dx: 5, dy: -5), .buttons(1), .keyboard(KeyboardReport(keys: [0x04])),
                            .click(button: 4, holdMs: 100), .keyboardSequence([KeyboardReport(modifiers: 1)], gapMs: 20)])
        #expect(b.client.flushWrites())
    }

    @Test func helperExitReportsLossAndReconnects() throws {
        let b = Bench()
        b.onQueue { b.client.autoReconnect = true }
        try b.onQueue { try b.client.connect(address: address) }
        b.links[0].emit(.state(.connected(address: address)))
        #expect(b.wait { b.state == .connected(address: address) })

        b.links[0].exit(9)   // kill -9 된 것처럼
        #expect(b.wait { b.recorder.states.contains(.disconnected(.helperLost)) })
        #expect(b.wait { b.links.count == 2 })
        // 새 도우미에 설정을 다시 보내고 기본 기기에 다시 연결한다
        let sent = b.links[1].sent
        #expect(sent.first == .setAutoReconnect(true))
        #expect(sent.last == .connect(address: address))
        #expect(b.state == .connecting(address: address))
    }

    @Test func noReconnectAfterUserDisconnect() throws {
        let b = Bench()
        b.onQueue { b.client.autoReconnect = true }
        try b.onQueue { try b.client.connect(address: address) }
        b.links[0].emit(.state(.connected(address: address)))
        b.onQueue { b.client.disconnect() }
        b.links[0].emit(.state(.disconnected(.user)))
        #expect(b.wait { b.state == .disconnected(.user) })
        b.links[0].exit(1)
        #expect(b.wait { b.links.count == 2 })
        #expect(!b.links[1].sent.contains { if case .connect = $0 { return true } else { return false } })
        // 끊긴 상태였으니 helperLost로 바꾸지 않는다
        #expect(!b.recorder.states.contains(.disconnected(.helperLost)))
    }

    @Test func eventsFromOldHelperAreIgnored() throws {
        let b = Bench()
        b.onQueue { b.client.startHelper() }
        let old = b.links[0]
        old.exit(9)
        #expect(b.wait { b.links.count == 2 })
        old.emit(.state(.connected(address: address)))
        b.links[1].emit(.state(.connecting(address: address)))
        #expect(b.wait { b.state == .connecting(address: address) })
        #expect(!b.recorder.states.contains(.connected(address: address)))
    }

    @Test func unresponsiveHelperIsKilledAndRelaunched() {
        var t = Bench.fastTiming()
        t.heartbeatTimeout = 0.3
        let b = Bench(timing: t)
        b.onQueue { b.client.startHelper() }
        // 하트비트를 보내는 동안엔 그대로
        for _ in 0..<5 { b.links[0].emit(.heartbeat); usleep(100_000) }
        #expect(b.links.count == 1)
        // 끊기면 죽이고 새로 띄운다
        #expect(b.wait { b.links.count == 2 })
        #expect(b.links[0].terminated)
    }

    @Test func silentHelperWhileConnectedAsksToReturnToMac() throws {
        var t = Bench.fastTiming()
        t.silentStall = 0.15
        let b = Bench(timing: t)
        try b.onQueue { try b.client.connect(address: address) }
        b.links[0].emit(.state(.connected(address: address)))
        #expect(b.wait { b.recorder.stalls == 1 })
        usleep(200_000)
        #expect(b.recorder.stalls == 1)   // 한 번만
        #expect(b.links.count == 1)       // 도우미는 아직 그대로
    }

    @Test func freshRestartIsRateLimitedAndReconnects() throws {
        let b = Bench()
        b.onQueue {
            b.client.autoReconnect = false   // 꺼져 있어도 거절 때문에 새로 띄운 것은 다시 연결한다
            b.client.defaultAddress = address
        }
        try b.onQueue { try b.client.connect(address: address) }
        b.links[0].emit(.state(.disconnected(.openFailed(stage: "제어 채널(0x11)", code: -536870212))))
        b.links[0].emit(.needsFreshProcess)
        #expect(b.wait { b.links.count == 2 })
        #expect(b.links[0].terminated)
        #expect(b.links[1].sent.last == .connect(address: address))
        // 30초 안에 또 오면 그대로 둔다
        b.links[1].emit(.needsFreshProcess)
        usleep(200_000)
        #expect(b.links.count == 2)
    }

    @Test func forwardsRejectedIncomingAndFailures() throws {
        let b = Bench()
        try b.onQueue { try b.client.connect(address: address) }
        b.links[0].emit(.incomingRejected(address: "00-11-22-33-44-66", name: "지민의 iPhone"))
        #expect(b.wait { b.recorder.rejected == ["00-11-22-33-44-66"] })
        b.links[0].emit(.failure("Mac 블루투스가 꺼져 있어요"))
        #expect(b.wait { b.state == .idle })   // "연결 중"에 머물지 않는다
    }

    @Test func rejectsBadInputWithoutLaunching() {
        let b = Bench()
        #expect(throws: BluetoothHID.HIDError.self) { try b.onQueue { try b.client.connect(address: "아이폰") } }
        b.client.bluetoothPoweredOn = { false }
        #expect(throws: BluetoothHID.HIDError.self) { try b.onQueue { try b.client.connect(address: address) } }
        #expect(b.links.isEmpty)
        #expect(!b.client.flushWrites(timeout: 0.05))
        #expect(b.client.takeMotionDiagnostics(timeout: 0.05) == nil)
    }

    @Test func restartPolicyBacksOffAndResetsWhenStable() {
        var p = HelperRestartPolicy()
        let t0 = Date()
        p.noteLaunched(at: t0)
        #expect([p.nextDelay(now: t0), p.nextDelay(now: t0), p.nextDelay(now: t0)] == [0.5, 2, 5])
        #expect([p.nextDelay(now: t0), p.nextDelay(now: t0), p.nextDelay(now: t0)] == [15, 30, 30])
        // 1분 넘게 잘 돌았으면 처음부터
        #expect(p.nextDelay(now: t0.addingTimeInterval(61)) == 0.5)
    }

    @Test func validatesAddresses() {
        #expect(HIDHelperClient.isValidAddress("00-11-22-33-44-55"))
        #expect(HIDHelperClient.isValidAddress("aa:bb:cc:dd:ee:ff"))
        #expect(!HIDHelperClient.isValidAddress("00-11-22-33-44"))
        #expect(!HIDHelperClient.isValidAddress(""))
    }
}

/// 실제 edgelink-hid를 띄워 블루투스 없이 주고받기만 확인한다 (SDP·연결은 하지 않음)
@Suite("도우미 프로세스", .serialized)
struct HelperProcessTests {
    static var helperURL: URL? {
        // 테스트 번들 옆, 없으면 패키지의 .build/debug (swift test가 실행 파일도 같이 만든다)
        var dirs = Bundle.allBundles.map { $0.bundleURL }.filter { $0.pathExtension == "xctest" }
            .map { $0.deletingLastPathComponent() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(root.appendingPathComponent(".build/debug"))
        for d in dirs {
            let u = d.appendingPathComponent("edgelink-hid")
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        return nil
    }

    @Test(.enabled(if: helperURL != nil, "swift build로 edgelink-hid를 먼저 만들어야 해요"))
    func pingFlushKillAndRelaunch() throws {
        let queue = DispatchQueue(label: "test.hid.process")
        var t = HIDHelperClient.Timing()
        t.restart = HelperRestartPolicy(delays: [0.1])
        let client = HIDHelperClient(launcher: HIDHelperClient.processLauncher(executable: Self.helperURL), queue: queue, timing: t)
        queue.sync { client.startHelper() }
        let pid1 = try #require(client.helperPID)
        // 도우미 메인 스레드가 답한다 (상태 질의)
        #expect(client.ping(timeout: 3))
        // 연결이 없어도 쓰기 큐 확인과 진단은 답한다
        client.move(dx: 1, dy: 1)
        #expect(client.flushWrites(timeout: 2))
        #expect(client.takeMotionDiagnostics(timeout: 2) != nil)

        // 강제 종료하면 다시 띄운다
        kill(pid1, SIGKILL)
        let end = Date().addingTimeInterval(5)
        var pid2: Int32?
        while Date() < end {
            if let p = queue.sync(execute: { client.helperPID }), p != pid1 { pid2 = p; break }
            usleep(20_000)
        }
        let newPID = try #require(pid2)
        #expect(queue.sync { client.launchCount } == 2)
        #expect(client.ping(timeout: 3))

        // 끝낼 때 도우미도 끝난다
        queue.sync { client.shutdown(timeout: 2) }
        #expect(kill(newPID, 0) != 0)
    }

    @Test(.enabled(if: helperURL != nil, "swift build로 edgelink-hid를 먼저 만들어야 해요"))
    func helperExitsWhenAppSideCloses() throws {
        // 앱이 죽은 것처럼 stdin만 닫아도 도우미는 스스로 끝난다
        let exited = DispatchSemaphore(value: 0)
        let link = try ProcessHelperLink(executable: try #require(Self.helperURL),
                                         handlers: HelperLinkHandlers(onEvent: { _ in }, onExit: { _ in exited.signal() }))
        #expect(link.send(HelperProtocol.frame(HelperCommand.ping(1).encode())))
        link.close()
        #expect(exited.wait(timeout: .now() + 4) == .success)
    }
}
