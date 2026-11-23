import AppKit
import Foundation

/// 扫描和执行共用的上下文：根路径、白名单、运行中的 App、当前时间都能注入，测试时用临时目录。
struct CleanContext: Sendable {
    /// 主目录。所有路径都从它推出来；测试时换成临时目录。
    var home: URL
    /// 用户白名单（绝对路径）。
    var whitelist: [String] = []
    /// 正在运行的 bundle id。nil 表示拿不到，此时一律当作在运行（G7）。
    var runningBundleIDs: Set<String>?
    /// 正在运行的进程名，用来判断 Gradle。nil 表示拿不到。
    var runningProcessNames: [String]?
    var now: Date = Date()
    var hasFullDiskAccess = false
    /// 已安装 App 的 bundle id（R6）。nil 表示清单不完整，R6 整类跳过。
    var installedBundleIDs: Set<String>?
    /// LaunchServices 里能不能找到这个 bundle id（R6 的第二重确认）。
    var launchServicesKnows: @Sendable (String) -> Bool = { _ in false }
    /// 项目构建产物的扫描目录（R7）。nil 用默认列表。
    var projectRoots: [URL]?
    /// 工具查找目录。
    var toolSearchDirectories: [URL] = CleanContext.defaultToolDirectories()
    /// 是否允许调用外部工具取信息（pnpm store path）。测试时关掉。
    var allowsToolQueries = true

    /// 主目录所在卷的设备号，G10 用。
    var homeDevice: Int32? { CleanFS.stat(home.path)?.device }

    static func defaultToolDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            "/opt/homebrew/bin", "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent("go/bin").path,
            "/usr/local/go/bin", "/opt/homebrew/opt/go/bin",
        ]
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 真实环境。
    @MainActor
    static func live(whitelist: [String] = []) -> CleanContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let apps = NSWorkspace.shared.runningApplications
        var ctx = CleanContext(home: home)
        ctx.whitelist = whitelist
        ctx.runningBundleIDs = Set(apps.compactMap(\.bundleIdentifier))
        ctx.runningProcessNames = CleanContext.processCommandLines()
        ctx.hasFullDiskAccess = CleanFS.probeFullDiskAccess(home: home)
        ctx.launchServicesKnows = { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
        }
        return ctx
    }

    /// 所有进程的命令行（小写比对用）。Gradle 守护进程是 java，只能从命令行里认。拿不到返回 nil。
    static func processCommandLines() -> [String]? {
        let command = ToolCommand(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axww", "-o", "command="],
            timeout: 10)
        guard let output = CleanToolRunner.output(command) else { return nil }
        return output.split(separator: "\n").map(String.init)
    }

    func library(_ sub: String) -> URL {
        home.appendingPathComponent("Library/\(sub)", isDirectory: true)
    }

    func findTool(_ name: String) -> URL? {
        for dir in toolSearchDirectories {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}

/// 文件系统小工具。
enum CleanFS {
    struct StatInfo {
        var device: Int32
        var inode: UInt64
        var mode: UInt16
        var isSymlink: Bool { (mode & 0o170000) == 0o120000 }
        var isDirectory: Bool { (mode & 0o170000) == 0o040000 }
        var isRegular: Bool { (mode & 0o170000) == 0o100000 }
        var fileID: CleanFileID { CleanFileID(device: device, inode: inode) }
    }

    /// `lstat`，不跟随符号链接。
    static func stat(_ path: String) -> StatInfo? {
        var st = Darwin.stat()
        guard lstat(path, &st) == 0 else { return nil }
        return StatInfo(device: st.st_dev, inode: UInt64(st.st_ino), mode: UInt16(st.st_mode))
    }

    /// 读 `~/Library/Safari` 能不能列出来，用来判断有没有完全磁盘访问。没授权时只是失败，不会弹窗。
    static func probeFullDiskAccess(home: URL) -> Bool {
        let url = home.appendingPathComponent("Library/Safari", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// 目录的直接子项；目录读不了返回 nil（无权限）。
    static func children(of url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [])
    }
}
