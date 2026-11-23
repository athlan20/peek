import Foundation

/// Analyze 扫描结果的缓存：再打开窗口（包括重启 Peek 后）直接显示上次的结果，用户点刷新才重扫。
///
/// 存在 `~/Library/Caches/Peek/analyze-cache.json`。只是缓存：读不出、版本不对就当没有，重扫即可。
/// 各个 worktree 的开发版和正式版共用这一份，格式变了就升 `currentVersion`，旧文件自动作废。
struct AnalyzeCache: Codable, Sendable {
    static let currentVersion = 1
    /// 最多记多少层目录，超出时丢掉最早扫的。
    static let maxListings = 200
    /// 子项太多的目录不进缓存，免得文件太大、读写太慢。
    static let maxItemsPerListing = 5_000

    struct Listing: Codable, Sendable, Equatable {
        var items: [AnalyzeItem]
        var totalBytes: UInt64
        var rootInaccessible: Bool
        /// 扫完（或停下）的时间。
        var scannedAt: Date
        /// 没扫完，停在这里；`items` 是停下时界面上的样子。
        var checkpoint: AnalyzeScanCheckpoint?
    }

    /// "Agent"页第一层量到一半停下的样子。
    struct AgentsPartial: Codable, Sendable, Equatable {
        var items: [AnalyzeItem]
        var checkpoint: AnalyzeAgentScan.Checkpoint
    }

    struct Agents: Codable, Sendable, Equatable {
        /// 第一层：每个 Agent 一块（虚拟 URL）。
        var agents: [AnalyzeItem]
        /// 第二层：每个 Agent 的目录，键是 Agent id。
        var paths: [String: [AnalyzeItem]]
        var scannedAt: Date
    }

    struct Downloads: Codable, Sendable, Equatable {
        var items: [AnalyzeItem]
        var scannedAt: Date
    }

    var version = currentVersion
    /// 键是目录路径。
    var listings: [String: Listing] = [:]
    var agents: Agents?
    /// 上次量到一半停下的；有它时优先接着量。
    var agentsPartial: AgentsPartial?
    var downloads: Downloads?

    // MARK: - 目录

    func listing(for url: URL) -> Listing? {
        guard url.isFileURL else { return nil }
        return listings[Self.key(url)]
    }

    mutating func store(_ listing: Listing, for url: URL) {
        guard url.isFileURL else { return }
        guard listing.items.count <= Self.maxItemsPerListing else {
            listings[Self.key(url)] = nil
            return
        }
        listings[Self.key(url)] = listing
        if listings.count > Self.maxListings {
            let oldest = listings.sorted { $0.value.scannedAt < $1.value.scannedAt }
                .prefix(listings.count - Self.maxListings)
            for (key, _) in oldest { listings[key] = nil }
        }
    }

    /// 文件移到废纸篓后：它自己和里面的缓存作废；缓存里的上级去掉它（或把包含它的子项缩小），总量减掉。
    mutating func forget(_ removed: AnalyzeItem) {
        let path = removed.url.standardizedFileURL.path
        let prefix = path.hasSuffix("/") ? path : path + "/"
        for key in Array(listings.keys) {
            if key == path || key.hasPrefix(prefix) {
                listings[key] = nil
                continue
            }
            let parentPrefix = key.hasSuffix("/") ? key : key + "/"
            guard path.hasPrefix(parentPrefix), var listing = listings[key] else { continue }
            listing.items = listing.items.compactMap { entry in
                let entryPath = entry.url.standardizedFileURL.path
                if entryPath == path { return nil }
                guard path.hasPrefix(entryPath + "/") else { return entry }
                return AnalyzeItem(
                    url: entry.url, name: entry.name, isDirectory: entry.isDirectory,
                    size: entry.size > removed.size ? entry.size - removed.size : 0,
                    isInaccessible: entry.isInaccessible)
            }
            listing.totalBytes = listing.totalBytes > removed.size ? listing.totalBytes - removed.size : 0
            listing.checkpoint?.forget(removed)
            listings[key] = listing
        }
        if var downloads {
            downloads.items.removeAll { entry in
                let entryPath = entry.url.standardizedFileURL.path
                return entryPath == path || entryPath.hasPrefix(prefix)
            }
            self.downloads = downloads
        }
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    // MARK: - 读写

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return base
            .appendingPathComponent("Peek", isDirectory: true)
            .appendingPathComponent("analyze-cache.json")
    }

    /// 读不到、解不开、版本不对都返回空缓存。
    static func load(from url: URL = defaultFileURL) -> AnalyzeCache {
        guard
            let data = try? Data(contentsOf: url),
            let cache = try? JSONDecoder().decode(AnalyzeCache.self, from: data),
            cache.version == currentVersion
        else { return AnalyzeCache() }
        return cache
    }

    func save(to url: URL = defaultFileURL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

extension AnalyzeScanCheckpoint {
    /// 文件移到废纸篓后：检查点里扫完的子项和各层的已量合计都把它去掉，接着扫时不会算回来。
    mutating func forget(_ removed: AnalyzeItem) {
        let path = removed.url.standardizedFileURL.path
        finished = finished.compactMap { entry in
            let entryPath = entry.url.standardizedFileURL.path
            if entryPath == path { return nil }
            guard path.hasPrefix(entryPath + "/") else { return entry }
            return AnalyzeItem(
                url: entry.url, name: entry.name, isDirectory: entry.isDirectory,
                size: entry.size > removed.size ? entry.size - removed.size : 0,
                isInaccessible: entry.isInaccessible)
        }
        for index in frames.indices where path.hasPrefix(frames[index].path + "/") {
            // 它在这一层已经量完（或在某个量完的子项里）才算进了合计。
            let rest = path.dropFirst(frames[index].path.count + 1)
            let child = String(rest.split(separator: "/").first ?? "")
            guard frames[index].doneNames.contains(child) else { continue }
            frames[index].doneBytes = frames[index].doneBytes > removed.size ? frames[index].doneBytes - removed.size : 0
            if rest == child { frames[index].doneNames.removeAll { $0 == child } }
        }
        scannedBytes = scannedBytes > removed.size ? scannedBytes - removed.size : 0
    }
}
