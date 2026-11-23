import Foundation
import Observation

/// 历史记录的类型：清理、卸载、维护。
enum HistoryKind: String, Codable, Sendable {
    case clean, uninstall, optimize
}

/// 一条历史记录。
struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var kind: HistoryKind
    /// 处理的条数。
    var itemCount: Int
    /// 释放的空间，没有则 0。
    var freedBytes: UInt64
    /// 失败的条数。
    var failedCount: Int
    /// 可选的简短说明，如维护项名称。
    var note: String?

    init(
        kind: HistoryKind,
        itemCount: Int,
        freedBytes: UInt64 = 0,
        failedCount: Int = 0,
        note: String? = nil,
        date: Date = Date()
    ) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.itemCount = itemCount
        self.freedBytes = freedBytes
        self.failedCount = failedCount
        self.note = note
    }
}

/// 历史记录文件格式的常量。
enum HistoryFileFormat {
    /// 当前写入的版本号。以后改格式要升版本并保证能读旧版本。
    static let version = 1
    /// 内存和文件里最多保留的条数。
    static let maxEntries = 500
}

/// 本地历史记录。清理、卸载、维护执行后调用 `record`。
///
/// 数据存 `~/Library/Application Support/Peek/history.json`，正式版和开发版共用。
/// 写入在后台队列做：先读磁盘最新内容，再追加并原子写入，避免多个进程互相覆盖。
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// 按时间从新到旧。
    private(set) var entries: [HistoryEntry] = []

    /// 累计计数。只保留最近 500 条记录算不出总量，所以单独存一份。
    private(set) var totals: HistoryTotals = .init()

    let fileURL: URL
    /// 累计计数文件，和 `fileURL` 同目录。
    let totalsFileURL: URL
    /// 磁盘上是更高版本时只读，不覆盖文件。
    private var isReadOnly = false

    private let writeQueue = DispatchQueue(label: "cc.yuntianyou.peek.history", qos: .utility)

    /// 默认路径。正式版和开发版（不同 worktree）共用同一个文件，不按 Bundle ID 分目录。
    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Peek", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// 最近一次清理的时间，没有则 nil。
    var lastCleaned: Date? {
        entries.first(where: { $0.kind == .clean })?.date
    }

    convenience init() {
        self.init(fileURL: Self.defaultFileURL)
    }

    /// 启动时同步读一次（文件很小），之后的读写都在后台。
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.totalsFileURL = Self.totalsURL(for: fileURL)
        switch Self.read(at: fileURL) {
        case .missing:
            entries = []
        case .corrupt:
            Self.backUpCorruptFile(at: fileURL)
            entries = []
        case .loaded(let existing, let readOnly):
            entries = existing
            isReadOnly = readOnly
        }

        // 累计计数文件不存在或损坏时，用现有记录一次性初始化并写盘。
        switch Self.readTotals(at: totalsFileURL) {
        case .loaded(let stored):
            totals = stored
        case .missing, .corrupt:
            totals = HistoryTotals.seed(from: entries)
            if !isReadOnly {
                Self.writeTotals(totals, to: totalsFileURL)
            }
        }
    }

    /// 追加一条记录。内存立即更新，文件在后台写入。
    func record(_ entry: HistoryEntry) {
        entries = Self.sortAndLimit(entries + [entry])
        totals = totals.adding(entry)
        guard !isReadOnly else { return }

        let url = fileURL
        let totalsURL = totalsFileURL
        writeQueue.async {
            Self.append(entry, to: url)
            Self.addTotals(entry, to: totalsURL, historyURL: url)
        }
    }

    /// 最近 `limit` 条，从新到旧。
    func recent(_ limit: Int) -> [HistoryEntry] {
        Array(entries.prefix(max(0, limit)))
    }
}

// MARK: - 文件读写（在后台队列执行）

extension HistoryStore {
    private struct FileContents: Codable, Sendable {
        var version: Int
        var entries: [HistoryEntry]
    }

    private struct VersionHeader: Decodable {
        let version: Int
    }

    private enum ReadResult: Sendable {
        case missing
        /// entries 已排好序、截到上限；readOnly 表示文件是更高的版本。
        case loaded(entries: [HistoryEntry], readOnly: Bool)
        case corrupt
    }

    nonisolated private static func read(at url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .corrupt }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let header = try? decoder.decode(VersionHeader.self, from: data) else { return .corrupt }

        if header.version > HistoryFileFormat.version {
            // 未来版本：尽力读出能用的字段，但绝不覆盖文件。
            let entries = (try? decoder.decode(FileContents.self, from: data))?.entries ?? []
            return .loaded(entries: sortAndLimit(entries), readOnly: true)
        }

        guard let file = try? decoder.decode(FileContents.self, from: data) else { return .corrupt }
        return .loaded(entries: sortAndLimit(file.entries), readOnly: false)
    }

    /// 后台写入：重新读磁盘最新内容再追加大，避免覆盖其他进程刚写的记录。
    nonisolated private static func append(_ entry: HistoryEntry, to url: URL) {
        var existing: [HistoryEntry]
        switch read(at: url) {
        case .missing:
            existing = []
        case .corrupt:
            backUpCorruptFile(at: url)
            existing = []
        case .loaded(let loaded, let readOnly):
            guard !readOnly else { return }
            existing = loaded
        }
        existing.append(entry)
        write(existing, to: url)
    }

    nonisolated private static func write(_ entries: [HistoryEntry], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = FileContents(version: HistoryFileFormat.version, entries: sortAndLimit(entries))
        guard let data = try? encoder.encode(contents) else { return }
        writeAtomically(data, to: url)
    }

    /// 先写临时文件，再 replace，避免写到一半被读到。
    nonisolated private static func writeAtomically(_ data: Data, to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    /// 损坏的文件备份为 `history.json.corrupt-<时间戳>`，然后从空开始。
    nonisolated private static func backUpCorruptFile(at url: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")

        if (try? FileManager.default.moveItem(at: url, to: backupURL)) == nil {
            // 同一秒已经存在同名备份时改用拷贝。
            try? FileManager.default.copyItem(at: url, to: backupURL)
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func sortAndLimit(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        Array(entries.sorted { $0.date > $1.date }.prefix(HistoryFileFormat.maxEntries))
    }
}

// MARK: - 累计计数文件（同目录的 history-totals.json）

extension HistoryStore {
    /// 累计计数文件名。和 `history.json` 同目录，正式版和开发版共用。
    nonisolated static var totalsFileName: String { "history-totals.json" }

    /// 累计计数文件跟着历史文件走，测试用临时目录时也一样。
    nonisolated static func totalsURL(for historyURL: URL) -> URL {
        historyURL.deletingLastPathComponent().appendingPathComponent(HistoryStore.totalsFileName)
    }

    enum TotalsReadResult: Sendable, Equatable {
        case missing
        case loaded(HistoryTotals)
        case corrupt
    }

    nonisolated static func readTotals(at url: URL) -> TotalsReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
            let totals = try? JSONDecoder().decode(HistoryTotals.self, from: data)
        else { return .corrupt }
        return .loaded(totals)
    }

    nonisolated static func writeTotals(_ totals: HistoryTotals, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(totals) else { return }
        writeAtomically(data, to: url)
    }

    /// 后台累加：先读磁盘最新值再加，两个进程同时写也不会丢计数。
    nonisolated private static func addTotals(_ entry: HistoryEntry, to url: URL, historyURL: URL) {
        let base: HistoryTotals = switch readTotals(at: url) {
        case .loaded(let stored): stored
        // 文件丢了或损坏：从 history.json 重新算，算的时候排除这一条，避免重复累加。
        case .missing, .corrupt: seedTotals(excluding: entry.id, fromHistory: historyURL)
        }
        writeTotals(base.adding(entry), to: url)
    }

    nonisolated private static func seedTotals(excluding id: UUID, fromHistory url: URL) -> HistoryTotals {
        guard case .loaded(let entries, _) = read(at: url) else { return HistoryTotals() }
        return HistoryTotals.seed(from: entries.filter { $0.id != id })
    }
}