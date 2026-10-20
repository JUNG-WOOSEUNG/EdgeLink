import Foundation
import EdgeLinkCore

/// 메인 스레드 멈춤 감시 (개발용 진단). 메뉴바·버튼이 반응하지 않는 순간을 찾으려고 둔다.
/// 0.5초마다 메인에 신호를 보내 0.3초 넘게 응답이 없으면 로그에 남기고,
/// 1초를 넘기면 그때의 호출 스택을 `sample`로 ~/Library/Logs/EdgeLink/hang-*.txt에 저장한다.
final class HangWatch {
    private let thread = Thread()
    private var lastSampleAt = Date.distantPast

    func start() {
        let t = Thread { [weak self] in self?.loop() }
        t.name = "EdgeLink 멈춤 감시"
        t.qualityOfService = .utility
        t.start()
    }

    private func loop() {
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            let answered = DispatchSemaphore(value: 0)
            let sent = DispatchTime.now()
            DispatchQueue.main.async { answered.signal() }
            if answered.wait(timeout: .now() + 0.3) == .success { continue }
            // 응답이 올 때까지 재되, 1초가 넘으면 스택을 한 번 남긴다
            var sampled = false
            while answered.wait(timeout: .now() + 0.2) == .timedOut {
                let ms = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1e6
                if !sampled, ms > 1000 { sampled = true; sampleNow() }
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1e6
            HIDLog.warn(String(format: "메인 스레드 멈춤 %.0fms%@", ms, sampled ? " (스택 저장함)" : ""))
        }
    }

    /// 너무 자주 남기지 않게 30초에 한 번까지
    private func sampleNow() {
        guard Date().timeIntervalSince(lastSampleAt) > 30 else { return }
        lastSampleAt = Date()
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/EdgeLink")
        let f = DateFormatter(); f.dateFormat = "HHmmss"
        let out = dir.appendingPathComponent("hang-\(f.string(from: Date())).txt")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "1", "-mayDie", "-file", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
