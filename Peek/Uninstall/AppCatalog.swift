import AppKit
import Foundation

/// 已安装 App 的列表和“能不能卸载”的判定。
enum AppCatalog {
    /// 扫描应用目录（含一层子文件夹），不量大小。
    static func list(context: UninstallContext) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for directory in context.applicationDirectories {
            collect(directory, depth: 0, context: context, into: &apps, seen: &seen)
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collect(_ directory: URL, depth: Int, context: UninstallContext, into apps: inout [InstalledApp], seen: inout Set<String>) {
        guard let children = CleanFS.children(of: directory) else { return }
        for child in children {
            if child.pathExtension == "app" {
                guard seen.insert(child.path).inserted, let app = makeApp(child, context: context) else { continue }
                apps.append(app)
            } else if depth < 1, let info = CleanFS.stat(child.path), info.isDirectory, !info.isSymlink {
                collect(child, depth: depth + 1, context: context, into: &apps, seen: &seen)
            }
        }
    }

    static func makeApp(_ url: URL, context: UninstallContext) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fileName
        let receipt = url.appendingPathComponent("Contents/_MASReceipt").path
        var app = InstalledApp(
            url: url, name: name, bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            isAppStore: FileManager.default.fileExists(atPath: receipt),
            bytes: nil, lastUsed: nil, blocked: nil)
        app.blocked = blockReason(path: url.path, bundleID: bundleID, context: context.clean)
        return app
    }

    // MARK: - 能不能卸载

    static let uninstallableApplePrefixes = [
        "com.apple.dt.", "com.apple.FinalCut", "com.apple.Motion", "com.apple.Compressor",
        "com.apple.logic", "com.apple.garageband", "com.apple.iMovie", "com.apple.iWork.",
        "com.apple.MainStage", "com.apple.Playgrounds",
    ]

    static let vendorManagedPrefixes = [
        "com.jamf", "com.crowdstrike", "com.sentinelone", "com.paloaltonetworks",
        "com.cisco.anyconnect", "com.cisco.secureclient", "com.eset", "com.microsoft.wdav",
    ]

    static func blockReason(path: String, bundleID: String, context: CleanContext) -> UninstallBlockReason? {
        if path.hasPrefix("/System/") { return .systemApp }
        if CleanGuard.peekBundleIDs.contains(bundleID) { return .peekItself }
        if bundleID.hasPrefix("com.apple.") || bundleID == "com.apple" {
            if !uninstallableApplePrefixes.contains(where: { bundleID.hasPrefix($0) || bundleID == String($0.dropLast()) }) {
                return .appleApp
            }
        }
        if vendorManagedPrefixes.contains(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") }) { return .vendorManaged }
        if CleanGuard.isExactlyRunning(bundleID, context: context) { return .running }
        return nil
    }

    // MARK: - 后台补充大小和最后使用时间

    static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return value as? Date
    }
}
