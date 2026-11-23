import Foundation

/// 按 `docs/uninstall-rules.md` 第 3 节查找一个 App 的残留。只在 `~/Library` 下找。
enum ResidualFinder {
    /// 名称匹配时不当作残留名的通用词（小写）。
    static let genericNames: Set<String> = ["code", "data", "cache", "helper", "support", "library", "updater", "update", "crash", "logs"]

    static func find(
        for app: InstalledApp,
        installed: [InstalledApp],
        context: UninstallContext,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> [ResidualItem] {
        let ctx = context.clean
        let B = app.bundleID
        let others = installed.filter { $0.id != app.id }
        let otherIDs = Set(others.map(\.bundleID))
        var measure = CleanMeasure()
        var found: [CleanFileID: ResidualItem] = [:]

        func add(_ url: URL, _ category: ResidualCategory, byName: Bool) {
            guard CleanGuard.check(url, context: ctx) == nil else { return }
            // 同一个文件可能被两条规则命中（路径写法不同），按（设备号, inode）去重。
            guard let info = CleanFS.stat(url.path), found[info.fileID] == nil else { return }
            guard let made = CleanItemFactory.make(url, rule: .r6, measure: &measure, isCancelled: isCancelled) else { return }
            var item = ResidualItem(
                url: url, category: category, bytes: made.item.bytes, isDirectory: made.item.isDirectory,
                fileID: made.item.fileID, matchedByName: byName)
            item.unreadable = made.hadUnreadable
            found[info.fileID] = item
        }

        /// 候选名属于另一个已安装 App（同族保护）。
        func belongsToOther(_ name: String) -> Bool {
            for o in otherIDs where name == o || name.hasPrefix(o + ".") { return true }
            return false
        }

        func lib(_ sub: String) -> URL { ctx.library(sub) }
        func children(_ sub: String) -> [URL] { CleanFS.children(of: lib(sub)) ?? [] }
        func exists(_ url: URL) -> Bool { CleanFS.stat(url.path) != nil }

        // 按 Bundle ID 精确匹配。
        let exact: [(sub: String, names: [String], category: ResidualCategory)] = [
            ("Caches", [B], .cache), ("Logs", [B], .cache),
            ("HTTPStorages", [B, B + ".binarycookies"], .cache), ("WebKit", [B], .cache),
            ("Cookies", [B + ".binarycookies"], .cache), ("Saved Application State", [B + ".savedState"], .cache),
            ("Preferences", [B + ".plist"], .settings), ("LaunchAgents", [B + ".plist"], .launchAgent),
            ("Application Scripts", [B], .settings),
            ("Application Support", [B], .personalData), ("Containers", [B], .personalData),
        ]
        for (sub, names, category) in exact {
            for name in names {
                let url = lib(sub).appendingPathComponent(name)
                if exists(url) { add(url, category, byName: false) }
            }
        }
        // `B.*.plist`：Preferences、ByHost、LaunchAgents。
        for (sub, category) in [("Preferences", ResidualCategory.settings), ("Preferences/ByHost", .settings), ("LaunchAgents", .launchAgent)] {
            for url in children(sub) {
                let name = url.lastPathComponent
                guard name.hasPrefix(B + "."), name.hasSuffix(".plist") else { continue }
                let stem = String(name.dropLast(".plist".count))
                if sub != "Preferences/ByHost", belongsToOther(stem) { continue }
                add(url, category, byName: false)
            }
        }
        // Group Containers：`group.B` 或 `<团队 ID>.B`。
        for url in children("Group Containers") {
            let name = url.lastPathComponent
            if name == "group." + B || isTeamPrefixed(name, bundleID: B) { add(url, .personalData, byName: false) }
        }

        // 按名称精确匹配：只有三处。
        let n = app.name
        if isUsableName(n), !others.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) {
            for (sub, category) in [("Application Support", ResidualCategory.personalData), ("Caches", .cache), ("Logs", .cache)] {
                for url in children(sub) where url.lastPathComponent.caseInsensitiveCompare(n) == .orderedSame {
                    if belongsToOther(url.lastPathComponent) { continue }
                    add(url, category, byName: url.lastPathComponent != B)
                }
            }
        }
        return found.values.sorted { lhs, rhs in
            if lhs.category != rhs.category { return order(lhs.category) < order(rhs.category) }
            return lhs.url.path < rhs.url.path
        }
    }

    static func isUsableName(_ name: String) -> Bool {
        name.count >= 4 && !genericNames.contains(name.lowercased())
    }

    static func isTeamPrefixed(_ name: String, bundleID: String) -> Bool {
        guard name.hasSuffix("." + bundleID) else { return false }
        let prefix = name.dropLast(bundleID.count + 1)
        return prefix.count == 10 && prefix.allSatisfy { $0.isUppercase || $0.isNumber }
    }

    private static func order(_ c: ResidualCategory) -> Int {
        switch c {
        case .settings: 0
        case .cache: 1
        case .launchAgent: 2
        case .personalData: 3
        }
    }
}
