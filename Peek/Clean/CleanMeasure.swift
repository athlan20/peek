import Foundation

/// 扫描时量大小、取最新修改时间。不跟随符号链接，硬链接只算一次（G3、G4）。
struct CleanMeasure {
    private(set) var seen: Set<CleanFileID> = []

    struct Result {
        var bytes: UInt64 = 0
        var newestModified: Date?
        var fileCount = 0
        /// 里面有读不了的目录。
        var hadUnreadable = false
    }

    /// 量一个路径（文件或目录）。同一个 `CleanMeasure` 里重复出现的硬链接只算一次。
    mutating func measure(_ url: URL, isCancelled: @Sendable () -> Bool = { false }) -> Result {
        var result = Result()
        guard let info = CleanFS.stat(url.path) else { return result }
        add(url, info: info, to: &result)
        guard info.isDirectory, !info.isSymlink else { return result }

        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        var unreadable = false
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in unreadable = true; return true })
        while let child = enumerator?.nextObject() as? URL {
            if isCancelled() { break }
            guard let childInfo = CleanFS.stat(child.path) else { continue }
            add(child, info: childInfo, to: &result)
        }
        result.hadUnreadable = unreadable
        return result
    }

    private mutating func add(_ url: URL, info: CleanFS.StatInfo, to result: inout Result) {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey])
        if let modified = values?.contentModificationDate {
            if result.newestModified == nil || modified > result.newestModified! { result.newestModified = modified }
        }
        result.fileCount += 1
        if info.isDirectory && !info.isSymlink { return }
        // 硬链接只计一次。目录没有硬链接问题，符号链接按自己的大小算。
        if !info.isSymlink, !seen.insert(info.fileID).inserted { return }
        let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
        result.bytes &+= UInt64(max(0, size))
    }
}

/// 候选条目的统一构造。
enum CleanItemFactory {
    /// 量大小、取 id，造一个条目。`url` 不存在返回 nil。
    static func make(
        _ url: URL,
        rule: CleanRuleID,
        measure: inout CleanMeasure,
        bundleID: String? = nil,
        appliesRecentCheck: Bool = false,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> (item: CleanItem, hadUnreadable: Bool)? {
        guard let info = CleanFS.stat(url.path) else { return nil }
        let r = measure.measure(url, isCancelled: isCancelled)
        let item = CleanItem(
            url: url,
            ruleID: rule,
            bytes: r.bytes,
            isDirectory: info.isDirectory && !info.isSymlink,
            fileID: info.fileID,
            bundleID: bundleID,
            modified: r.newestModified,
            appliesRecentCheck: appliesRecentCheck)
        return (item, r.hadUnreadable)
    }
}
