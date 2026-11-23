import Foundation

/// 不能卸载的原因（`docs/uninstall-rules.md` 第 1 节）。
enum UninstallBlockReason: String, Sendable, Equatable {
    case systemApp
    case peekItself
    case appleApp
    case vendorManaged
    case running
}

struct InstalledApp: Identifiable, Sendable, Equatable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    let isAppStore: Bool
    /// 后台量完才有。
    var bytes: UInt64?
    var lastUsed: Date?
    var blocked: UninstallBlockReason?
}

enum ResidualCategory: String, Sendable, CaseIterable {
    case settings, cache, launchAgent, personalData
}

struct ResidualItem: Identifiable, Sendable, Equatable {
    var id: String { url.path }
    let url: URL
    let category: ResidualCategory
    let bytes: UInt64
    let isDirectory: Bool
    let fileID: CleanFileID?
    /// 按名称而不是 Bundle ID 匹配到的，预览里要标出。
    let matchedByName: Bool
    /// 个人数据默认不勾选。
    var defaultSelected: Bool { category != .personalData }
    /// 读不了（如 Containers 没有完全磁盘访问）。
    var unreadable = false
}

struct UninstallOutcome: Sendable, Equatable {
    var appRemoved = false
    var appFailureReason: String?
    var processed = 0
    var freedBytes: UInt64 = 0
    var failed = 0
    var skipped: [CleanSkipped] = []
}

/// 注入用的环境。路径、运行中的 App、已安装 App 列表都能换成测试数据。
struct UninstallContext: Sendable {
    var clean: CleanContext
    var applicationDirectories: [URL]

    @MainActor
    static func live(whitelist: [String] = []) -> UninstallContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UninstallContext(
            clean: CleanContext.live(whitelist: whitelist),
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
            ])
    }
}
