import Foundation

/// 累计计数：清理释放的总字节、卸载的项数、优化的项数。
///
/// `HistoryStore` 只保留最近 500 条，所以累加值单独存一份（`history-totals.json`），
/// 不能从 `entries` 求和。加法的含义见 `adding(_:)`。
struct HistoryTotals: Codable, Sendable, Equatable {
    /// 清理累计释放的空间（字节）。
    var cleanedBytes: UInt64 = 0
    /// 卸载过的 App 个数(每条卸载记录 = 一个 App 被卸掉)。
    var uninstalledCount: Int = 0
    /// 优化执行的次数(每条优化记录算一次)。
    var optimizedCount: Int = 0

    /// 加上一条历史记录。清理累加释放的字节;卸载、优化各算一次(卸载只在 App 本体被移除时才有记录)。
    func adding(_ entry: HistoryEntry) -> HistoryTotals {
        var totals = self
        switch entry.kind {
        case .clean:
            totals.cleanedBytes += entry.freedBytes
        case .uninstall:
            totals.uninstalledCount += 1
        case .optimize:
            totals.optimizedCount += 1
        }
        return totals
    }

    /// 从一批记录算出累计值。`history-totals.json` 不存在时用它一次性初始化。
    static func seed(from entries: [HistoryEntry]) -> HistoryTotals {
        entries.reduce(HistoryTotals()) { $0.adding($1) }
    }
}