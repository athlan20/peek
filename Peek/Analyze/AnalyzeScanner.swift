import Foundation

/// 分析窗口里的一个条目。
struct AnalyzeItem: Identifiable, Hashable, Sendable, Codable {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// 磁盘实际占用。文件夹是递归总和；无权限的目录为 0，不计入上级总量。
    let size: UInt64
    /// 目录本身读不到（无权限）时为 true，界面上标“无权限”。
    let isInaccessible: Bool

    var id: URL { url }
}

/// 扫描进度：已扫描的字节数和条目数，够界面显示“正在扫描”用。
struct AnalyzeScanProgress: Sendable, Equatable {
    var scannedBytes: UInt64 = 0
    var itemCount: Int = 0
    /// 扫到一半时当前目录的直接子项：扫完的按最终大小，正在扫的按目前量到的大小，还没轮到的不在里面。
    /// 方块视图靠它边扫边长；没有就是 nil。
    var items: [AnalyzeItem]?
}

/// 一次目录扫描的结果。
struct AnalyzeScanResult: Sendable {
    /// 当前目录的直接子项，按大小从大到小。
    var items: [AnalyzeItem] = []
    /// 可读子项的递归总和。无权限的目录不计入。
    var totalBytes: UInt64 = 0
    /// 当前目录下最大的文件（>= 100 MB，最多 50 个）。
    var largeFiles: [AnalyzeItem] = []
    /// 根目录本身读不到（无权限）。
    var rootInaccessible = false
    /// 扫描被取消（或暂停），结果不完整。
    var wasCancelled = false
    /// 取消时扫到的位置，交给下一次 `scan(resume:)` 接着扫。
    var checkpoint: AnalyzeScanCheckpoint?
}

/// 扫到一半停下时的位置，可以存盘，下次接着扫。
///
/// 第一层记扫完的子项（含最终大小）；正在扫的那个子项里，沿着当前递归路径每一层目录记
/// "哪些子项已经量完、合计多少"。接着扫时跳过这些，正在量的那个文件夹从头量。
/// 硬链接去重只在一次扫描内有效，接着扫时前后两段之间的硬链接可能重复计算。
struct AnalyzeScanCheckpoint: Codable, Sendable, Equatable {
    struct Frame: Codable, Sendable, Equatable {
        var path: String
        var doneNames: [String]
        var doneBytes: UInt64
    }

    /// 第一层扫完的子项。
    var finished: [AnalyzeItem] = []
    /// 正在扫的那个第一层子项里，从外到内每层目录的进度。
    var frames: [Frame] = []
    var scannedBytes: UInt64 = 0
    var itemCount = 0
}

/// 磁盘扫描器。和 UI 无关，都是同步函数，方便单独用小命令行程序测试。
///
/// 大小口径：
/// - 用磁盘实际占用（`totalFileAllocatedSizeKey`，取不到退回 `fileAllocatedSizeKey` / `fileSizeKey`）。
/// - 不跟随符号链接：链接本身按 `fileSize`（链接路径的长度）算，不进入目标。
/// - 硬链接按 `(设备号, inode)`（`fileResourceIdentifier` 的字节表示）在单次扫描内去重，只算第一次出现的。
/// - 文件夹大小是子项递归总和，不额外算目录自身的元数据。
enum AnalyzeScanner {
    /// 大文件的下限。
    static let largeFileThreshold: UInt64 = 100 * 1024 * 1024
    /// 大文件列表最多显示的条数。
    static let maxLargeFiles = 50
    /// 旧下载的年龄下限。
    static let oldDownloadAge: TimeInterval = 90 * 24 * 60 * 60

    /// 扫描启动盘 `/` 时要跳过的路径（只在根目录是 `/` 时生效）。
    ///
    /// - `/System/Volumes`：APFS 卷宗（Data、Preboot、VM 等）的挂载点，和系统卷是同一块物理盘，
    ///   走进去会把同一批文件重复计算。
    /// - `/Volumes`：外接盘和其他卷的挂载点，不属于启动盘。
    /// - `/dev`：设备节点，不是真实文件，也没有有意义的大小。
    /// - `/private/var/vm`：swap 和休眠镜像，系统管理、稀疏且经常变动，算进来没有参考价值。
    static let startupDiskSkippedPaths: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/private/var/vm",
    ]

    fileprivate static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .fileResourceIdentifierKey, .contentModificationDateKey,
    ]

    /// 扫描 `root` 的直接子项，并递归统计大小、收集大文件。
    ///
    /// 同步执行，调用方应放在后台任务里；`isCancelled` 每处理一个条目检查一次。
    /// `resume` 是上次停下的位置：扫完的子项直接沿用，没扫完的接着扫。
    static func scan(
        root: URL,
        resume: AnalyzeScanCheckpoint? = nil,
        progress: (@Sendable (AnalyzeScanProgress) -> Void)? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> AnalyzeScanResult {
        var walker = Walker(collectLargeFiles: true, progress: progress, isCancelled: isCancelled)
        var result = AnalyzeScanResult()

        guard let entries = walker.list(root) else {
            result.rootInaccessible = true
            result.wasCancelled = walker.cancelled
            if walker.cancelled { result.checkpoint = resume ?? AnalyzeScanCheckpoint() }
            return result
        }

        // 接着上次扫：扫完的子项照搬，各层进度交给 walker 跳过。
        var finished: [AnalyzeItem] = resume?.finished ?? []
        let finishedNames = Set(finished.map(\.name))
        let resumeFrames = resume?.frames ?? []
        walker.resume = Dictionary(resumeFrames.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        walker.restore(
            scannedBytes: resume?.scannedBytes ?? 0,
            itemCount: resume?.itemCount ?? 0)
        for item in finished {
            result.items.append(item)
            if !item.isInaccessible { result.totalBytes += item.size }
        }

        // 中途快照：扫完的子项 + 正在扫的那个（大小 = 进入它以后量到的字节数，含上次已量的部分）。
        var current: (url: URL, isDirectory: Bool, startBytes: UInt64)?
        walker.snapshot = { scannedBytes in
            guard let current else { return finished }
            return finished + [AnalyzeItem(
                url: current.url,
                name: current.url.lastPathComponent,
                isDirectory: current.isDirectory,
                size: scannedBytes &- current.startBytes,
                isInaccessible: false)]
        }
        walker.reportProgress(force: true)

        let skipPaths = root.path == "/" ? startupDiskSkippedPaths : []
        for (url, values) in entries {
            if finishedNames.contains(url.lastPathComponent) { continue }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            // 上次在这个子项里已经量过的部分。
            let path = url.path
            let restored = resumeFrames
                .filter { $0.path == path || $0.path.hasPrefix(path + "/") }
                .reduce(UInt64(0)) { $0 &+ $1.doneBytes }
            current = (url, isDirectory, walker.scannedBytes &- restored)
            let measurement = walker.measure(url, values: values, skipPaths: skipPaths)
            current = nil
            if walker.cancelled { break }
            if measurement.skipped { continue }
            let item = AnalyzeItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                size: measurement.bytes,
                isInaccessible: !measurement.accessible)
            result.items.append(item)
            finished.append(item)
            if measurement.accessible {
                result.totalBytes += measurement.bytes
            }
        }

        if walker.cancelled {
            // 发现取消时路径上各层的进度，加上这次还没走到、上次留下的进度（仍然有效）。
            let frames = (walker.checkpointFrames + walker.resume.values)
                .sorted { $0.path.count < $1.path.count }
            let doneBytes = finished.filter { !$0.isInaccessible }.reduce(UInt64(0)) { $0 &+ $1.size }
                &+ frames.reduce(UInt64(0)) { $0 &+ $1.doneBytes }
            result.checkpoint = AnalyzeScanCheckpoint(
                finished: finished, frames: frames, scannedBytes: doneBytes, itemCount: walker.itemCount)
        }

        result.items.sort { lhs, rhs in
            lhs.size == rhs.size ? lhs.name < rhs.name : lhs.size > rhs.size
        }
        result.largeFiles = Array(
            walker.largeFiles
                .sorted { $0.size == $1.size ? $0.name < $1.name : $0.size > $1.size }
                .prefix(maxLargeFiles))
        result.wasCancelled = walker.cancelled
        return result
    }

    /// `~/Downloads` 里最后修改时间超过 90 天的直接子项，按大小从大到小。
    ///
    /// 只看下载目录的一层，不递归找旧文件；每个子项的大小仍然递归统计。
    static func oldDownloads(
        in downloads: URL? = nil,
        now: Date = Date(),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [AnalyzeItem] {
        let directory = downloads
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
        var walker = Walker(collectLargeFiles: false, progress: nil, isCancelled: isCancelled)

        guard let entries = walker.list(directory) else { return [] }
        var items: [AnalyzeItem] = []
        for (url, values) in entries {
            guard
                let modified = values.contentModificationDate,
                now.timeIntervalSince(modified) > oldDownloadAge
            else { continue }
            // 启动盘跳过列表只对 `/` 生效，下载目录里照常算。
            let measurement = walker.measure(url, values: values, skipPaths: [])
            items.append(
                AnalyzeItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: values.isDirectory == true && values.isSymbolicLink != true,
                    size: measurement.bytes,
                    isInaccessible: !measurement.accessible))
            if walker.cancelled { return [] }
        }
        return items.sorted { lhs, rhs in
            lhs.size == rhs.size ? lhs.name < rhs.name : lhs.size > rhs.size
        }
    }
}

// MARK: - 遍历

private struct Walker {
    struct Measurement {
        var bytes: UInt64
        var accessible: Bool
        /// 命中启动盘跳过列表，界面上不列出。
        var skipped = false

        static let inaccessible = Measurement(bytes: 0, accessible: false)
        static let skippedPath = Measurement(bytes: 0, accessible: true, skipped: true)
    }

    let collectLargeFiles: Bool
    let progress: (@Sendable (AnalyzeScanProgress) -> Void)?
    let isCancelled: @Sendable () -> Bool

    /// 单次扫描里出现过的 (设备号, inode)，硬链接去重用。
    private var visited: Set<Data> = []
    private(set) var largeFiles: [AnalyzeItem] = []
    private(set) var cancelled = false

    /// 给进度附上当前目录子项的中途快照，参数是到目前为止量到的总字节数。
    var snapshot: ((UInt64) -> [AnalyzeItem])?
    /// 接着上次扫：按目录路径查上次量完的子项。用过就删。
    var resume: [String: AnalyzeScanCheckpoint.Frame] = [:]
    /// 当前递归路径上每层目录的进度。
    private var frames: [AnalyzeScanCheckpoint.Frame] = []
    /// 发现取消的那一刻的 `frames`，存成检查点。
    private(set) var checkpointFrames: [AnalyzeScanCheckpoint.Frame] = []

    private(set) var scannedBytes: UInt64 = 0
    private(set) var itemCount = 0
    private var lastReport = Date.distantPast

    init(
        collectLargeFiles: Bool,
        progress: (@Sendable (AnalyzeScanProgress) -> Void)?,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.collectLargeFiles = collectLargeFiles
        self.progress = progress
        self.isCancelled = isCancelled
    }

    /// 列出一层目录。隐藏项（如 `~/Library`）要包含，所以 options 为空。读不到返回 nil。
    mutating func list(_ directory: URL) -> [(URL, URLResourceValues)]? {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(AnalyzeScanner.resourceKeys),
                options: [])
        else { return nil }

        var entries: [(URL, URLResourceValues)] = []
        entries.reserveCapacity(urls.count)
        for url in urls {
            if shouldCancel() { return entries }
            guard let values = try? url.resourceValues(forKeys: AnalyzeScanner.resourceKeys) else {
                continue
            }
            entries.append((url, values))
        }
        return entries
    }

    mutating func measure(
        _ url: URL,
        values: URLResourceValues,
        skipPaths: Set<String>
    ) -> Measurement {
        if shouldCancel() { return .inaccessible }
        guard !skipPaths.contains(url.path) else { return .skippedPath }

        // 符号链接不跟随，按链接自身的大小算（链接的 allocated size 是 0，用 fileSize）。
        if values.isSymbolicLink == true {
            let bytes = UInt64(max(0, values.fileSize ?? 0))
            note(bytes: bytes)
            return Measurement(bytes: bytes, accessible: true)
        }

        if values.isDirectory == true {
            guard let entries = list(url) else { return .inaccessible }
            // 列目录时就被取消了：上次留下的进度别动，下次还要用。
            if cancelled { return .inaccessible }
            let previous = resume.removeValue(forKey: url.path)
            let skip = Set(previous?.doneNames ?? [])
            var total = previous?.doneBytes ?? 0
            frames.append(AnalyzeScanCheckpoint.Frame(
                path: url.path, doneNames: previous?.doneNames ?? [], doneBytes: total))
            let index = frames.count - 1
            defer { frames.removeLast() }
            for (childURL, childValues) in entries {
                if cancelled { break }
                let name = childURL.lastPathComponent
                if skip.contains(name) { continue }
                let child = measure(childURL, values: childValues, skipPaths: skipPaths)
                // 量到一半被取消的子项不算量完。
                if cancelled { break }
                if child.accessible { total += child.bytes }
                frames[index].doneNames.append(name)
                frames[index].doneBytes = total
            }
            return Measurement(bytes: total, accessible: !cancelled)
        }

        var bytes = Self.allocatedBytes(values)

        // 硬链接去重：同一个 (设备号, inode) 只算第一次。拿不到标识时按普通文件累加。
        if let identifier = values.fileResourceIdentifier as? Data {
            if visited.contains(identifier) {
                bytes = 0
            } else {
                visited.insert(identifier)
            }
        }

        note(bytes: bytes)
        if collectLargeFiles, bytes >= AnalyzeScanner.largeFileThreshold {
            largeFiles.append(
                AnalyzeItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: false,
                    size: bytes,
                    isInaccessible: false))
        }
        return Measurement(bytes: bytes, accessible: !cancelled)
    }

    mutating func reportProgress(force: Bool = false) {
        guard let progress else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.2 else { return }
        lastReport = now
        progress(AnalyzeScanProgress(scannedBytes: scannedBytes, itemCount: itemCount, items: snapshot?(scannedBytes)))
    }

    mutating func restore(scannedBytes: UInt64, itemCount: Int) {
        self.scannedBytes = scannedBytes
        self.itemCount = itemCount
    }

    private mutating func shouldCancel() -> Bool {
        if !cancelled, isCancelled() {
            cancelled = true
            checkpointFrames = frames
        }
        return cancelled
    }

    private mutating func note(bytes: UInt64) {
        scannedBytes += bytes
        itemCount += 1
        reportProgress()
    }

    private static func allocatedBytes(_ values: URLResourceValues) -> UInt64 {
        if let total = values.totalFileAllocatedSize, total > 0 { return UInt64(total) }
        if let allocated = values.fileAllocatedSize, allocated > 0 { return UInt64(allocated) }
        return UInt64(max(0, values.fileSize ?? 0))
    }
}