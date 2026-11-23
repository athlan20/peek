import Foundation

/// 固定容量的样本缓冲：满了丢最旧的。面板上的趋势小图用它存最近 60 个样本。
/// 纯值类型，不落盘，可以在任意线程传递。
struct SampleHistory: Sendable, Equatable {
    /// 面板小图用的容量：面板每秒采一次，正好 60 秒。
    static let defaultCapacity = 60

    let capacity: Int
    private(set) var values: [Double]

    /// `values` 超过容量时只留最新的若干个。
    init(capacity: Int = SampleHistory.defaultCapacity, values: [Double] = []) {
        let capacity = max(1, capacity)
        self.capacity = capacity
        self.values = Array(values.suffix(capacity))
    }

    mutating func append(_ value: Double) {
        values.append(value)
        let overflow = values.count - capacity
        if overflow > 0 {
            values.removeFirst(overflow)
        }
    }
}