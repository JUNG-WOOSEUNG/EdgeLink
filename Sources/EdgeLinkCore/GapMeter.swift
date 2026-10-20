import Foundation

/// 이벤트 사이 간격 재기 (움직임 끊김 진단용). 같은 스레드에서만 쓴다.
public struct GapMeter {
    public struct Summary: CustomStringConvertible {
        public let count: Int
        public let averageMs: Double
        public let maxMs: Double
        /// 간격이 30ms를 넘은 횟수 (눈에 보이는 끊김 후보)
        public let longGaps: Int

        public var description: String {
            count == 0 ? "없음" : String(format: "%d개 · 간격 평균 %.1fms · 최대 %.1fms · 30ms 넘음 %d번", count, averageMs, maxMs, longGaps)
        }
    }

    private var last: UInt64 = 0
    private var count = 0
    private var sum: Double = 0
    private var maxGap: Double = 0
    private var long = 0
    /// 이보다 긴 간격은 "멈춤"으로 보고 세지 않는다 (손을 뗀 시간)
    public var idleCutoffMs: Double = 250

    public init() {}

    public mutating func tick(_ now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        defer { last = now; count += 1 }
        guard last != 0 else { return }
        let gap = Double(now &- last) / 1e6
        guard gap < idleCutoffMs else { return }
        sum += gap
        maxGap = max(maxGap, gap)
        if gap > 30 { long += 1 }
    }

    /// 지금까지의 요약을 돌려주고 비운다 (마지막 시각은 남겨 다음 구간으로 잇는다)
    public mutating func take() -> Summary {
        let gaps = max(count - 1, 0)
        let s = Summary(count: count, averageMs: gaps > 0 ? sum / Double(gaps) : 0, maxMs: maxGap, longGaps: long)
        count = 0; sum = 0; maxGap = 0; long = 0
        return s
    }
}
