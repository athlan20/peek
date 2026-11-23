import Foundation

/// 规则 id，对应 `docs/clean-rules.md`。
enum CleanRuleID: String, Sendable, CaseIterable, Codable {
    case r1, r2, r3, r4, r5, r6, r7, r8, r9, f1, f2

    var label: String { rawValue.uppercased() }
}

/// 一条工具命令。只用绝对路径，设超时。
struct ToolCommand: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var timeout: TimeInterval = 120
}

/// 删除方式（文档第 1 节）。
enum CleanDeleteMethod: Sendable, Equatable {
    /// 直接删。
    case remove
    /// 移到废纸篓。
    case trash
    /// 调用工具自己的清理命令。
    case tool(ToolCommand)
    /// 通过 Finder 清空废纸篓（不可恢复）。
    case finderEmptyTrash
}

/// 跳过的原因。
enum CleanSkipReason: String, Sendable, Equatable {
    case noPermission
    case appRunning
    case browserRunning
    case recentlyUsed
    case protectedApp
    case protectedPath
    case whitelisted
    case invalidPath
    case symlinkRoot
    case otherVolume
    case changed
    case toolMissing
    case downloading
    case inUse
    case appListIncomplete
    case failed
}

/// （设备号，inode），用来给硬链接去重，也用来确认执行时还是扫描时那个文件。
struct CleanFileID: Hashable, Sendable {
    var device: Int32
    var inode: UInt64
}

/// 一个要删的具体路径。
struct CleanItem: Identifiable, Sendable, Equatable {
    var id: String { url.path }
    let url: URL
    let ruleID: CleanRuleID
    /// 实际占用，已去掉硬链接重复计算。
    let bytes: UInt64
    let isDirectory: Bool
    let fileID: CleanFileID?
    /// 缓存目录名里的 bundle id，用于 G7；没有则 nil。
    let bundleID: String?
    /// 最后修改时间（目录取里面最新的）。
    let modified: Date?
    /// 是否适用 G8（60 分钟内被修改过就跳过）。
    let appliesRecentCheck: Bool
}

struct CleanSkipped: Sendable, Equatable {
    let path: String
    let reason: CleanSkipReason
}

/// 界面上的一行：一个缓存目录名、一个开发工具、一个浏览器等。
struct CleanGroup: Identifiable, Sendable, Equatable {
    let id: String
    let ruleID: CleanRuleID
    var title: String
    var items: [CleanItem]
    var skipped: [CleanSkipped] = []
    var method: CleanDeleteMethod
    /// 这些 bundle id 里任何一个在运行，整组都不执行（浏览器、Xcode、Safari）。
    var requiresNotRunning: [String] = []
    /// 进程名里含这些片段的进程在运行，整组不执行（Gradle）。
    var blockingProcessFragments: [String] = []
    /// R6：来自 Application Support，预览里单独标出。
    var isApplicationSupport = false
    /// 没有逐项路径时用的大小（废纸篓）。
    var fixedBytes: UInt64?

    var bytes: UInt64 { fixedBytes ?? items.reduce(0) { $0 &+ $1.bytes } }
}

struct CleanCategory: Identifiable, Sendable, Equatable {
    var id: CleanRuleID { ruleID }
    let ruleID: CleanRuleID
    var groups: [CleanGroup]
    let defaultSelected: Bool
    /// 整类跳过的原因，如 R6 的 App 清单不完整。
    var skippedReason: CleanSkipReason?

    var bytes: UInt64 { groups.reduce(0) { $0 &+ $1.bytes } }
    var itemCount: Int { groups.reduce(0) { $0 + max($1.items.count, $1.fixedBytes == nil ? 0 : 1) } }
}

/// 执行结果。
struct CleanOutcome: Sendable, Equatable {
    var processed = 0
    var freedBytes: UInt64 = 0
    var failed = 0
    var skipped: [CleanSkipped] = []
    var wasCancelled = false
}
