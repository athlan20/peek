import Foundation

/// G1–G11 的唯一判定入口。扫描和执行都调 `check`，各规则不自己写保护判断。
enum CleanGuard {
    // MARK: - G1 路径规范化

    /// 绝对路径、不含 `..`、不含控制字符；规范化重复斜杠和末尾斜杠。不合格返回 nil。
    static func normalized(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return nil }
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == ".." { return nil }
            if part == "." { continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    // MARK: - G2 保护路径

    /// 本身和祖先都不能删的路径（容器、系统目录）。
    static func protectedExact(home: String) -> [String] {
        let system = ["/", "/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/Library", "/Applications", "/Users"]
        let library = [
            "Library", "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Group Containers", "Library/Preferences", "Downloads",
        ].map { home + "/" + $0 }
        return system + [home] + library
    }

    /// 本身和整棵子树都不能碰的路径。
    static func protectedSubtrees(home: String) -> [String] {
        [
            "Documents", "Desktop", "Pictures", "Movies", "Music", "Public",
            "Library/Mobile Documents",
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Safari",
            ".ssh", ".gnupg", ".aws", ".kube",
            "Library/Application Support/Peek",
        ].map { home + "/" + $0 }
    }

    static let peekBundleIDs = ["cc.yuntianyou.peek", "cc.yuntianyou.peek.dev"]

    /// 判定一个已规范化的路径。返回跳过原因，nil 表示通过。
    static func checkNormalized(_ path: String, home: String, whitelist: [String]) -> CleanSkipReason? {
        // G6 白名单：按路径组件前缀匹配。
        for entry in whitelist {
            guard let w = normalized(entry) else { continue }
            if path == w || path.hasPrefix(w + "/") { return .whitelisted }
        }
        // G2 容器和系统目录：路径本身或它的祖先。
        for p in protectedExact(home: home) where path == p || (p != "/" && p.hasPrefix(path + "/")) || path == "/" {
            return .protectedPath
        }
        for p in protectedSubtrees(home: home) where path == p || path.hasPrefix(p + "/") || p.hasPrefix(path + "/") {
            return .protectedPath
        }
        // 照片库在任意位置。
        for component in path.split(separator: "/") where component.lowercased().hasSuffix(".photoslibrary") {
            return .protectedPath
        }
        // Peek 自己的缓存、偏好、容器。
        for id in peekBundleIDs {
            for sub in ["Library/Caches", "Library/Preferences", "Library/Containers", "Library/Application Support",
                        "Library/Logs", "Library/HTTPStorages", "Library/Saved Application State", "Library/WebKit"] {
                let base = home + "/" + sub + "/" + id
                if path == base || path.hasPrefix(base + "/") || path.hasPrefix(base + ".") { return .protectedPath }
            }
        }
        return nil
    }

    // MARK: - 完整检查（G1、G2、G3、G6、G10）

    /// 对一个路径做完整的安全检查。通过返回 nil。
    static func check(_ url: URL, context: CleanContext, requireSameVolume: Bool = true) -> CleanSkipReason? {
        guard let path = normalized(url.path) else { return .invalidPath }
        let home = normalizedHome(context)
        if let reason = checkNormalized(path, home: home, whitelist: context.whitelist) { return reason }

        // G3 物理位置：父目录解析符号链接后再检查一遍（条目本身是链接时只管链接自己）。
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
        let name = (path as NSString).lastPathComponent
        let real = (parent == "/" ? "" : parent) + "/" + name
        if real != path {
            let realHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
            let resolvedWhitelist = context.whitelist.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            if let reason = checkNormalized(real, home: realHome, whitelist: context.whitelist + resolvedWhitelist) {
                return reason
            }
            if let reason = checkNormalized(real, home: home, whitelist: context.whitelist + resolvedWhitelist) {
                return reason
            }
        }

        // G10 只处理主目录所在的启动卷。
        if requireSameVolume, let homeDevice = context.homeDevice,
           let info = CleanFS.stat(path), info.device != homeDevice {
            return .otherVolume
        }
        return nil
    }

    static func normalizedHome(_ context: CleanContext) -> String {
        normalized(context.home.path) ?? context.home.path
    }

    // MARK: - G7、G8 与保留清单

    /// G7：对应 App 是否在运行。拿不到运行列表时当作在运行。
    static func isAppRunning(_ bundleID: String, context: CleanContext) -> Bool {
        guard let running = context.runningBundleIDs else { return true }
        for r in running where r == bundleID || r.hasPrefix(bundleID + ".") || bundleID.hasPrefix(r + ".") {
            return true
        }
        return false
    }

    /// 精确匹配（浏览器、Xcode、Safari 用）。拿不到运行列表时当作在运行。
    static func isExactlyRunning(_ bundleID: String, context: CleanContext) -> Bool {
        guard let running = context.runningBundleIDs else { return true }
        return running.contains(bundleID)
    }

    /// G8：最近 60 分钟内被修改过。
    static let recentWindow: TimeInterval = 60 * 60

    static func isRecentlyUsed(_ modified: Date?, context: CleanContext) -> Bool {
        guard let modified else { return false }
        return context.now.timeIntervalSince(modified) < recentWindow
    }

    /// 第 3 节保留清单。只按 bundle id 前缀（点边界）匹配。
    static let protectedAppPrefixes: [String] = [
        "com.apple",
        "com.1password", "com.agilebits", "com.bitwarden", "org.keepassxc", "com.lastpass", "com.dashlane",
        "com.wireguard", "net.mullvad", "com.nordvpn", "com.expressvpn", "com.clash", "com.surge",
        "com.getdropbox.dropbox", "com.microsoft.OneDrive", "com.google.GoogleDrive",
        "com.docker", "com.orbstack", "com.utmapp", "com.parallels", "com.vmware",
        "im.rime", "com.sogou", "com.baidu.inputmethod", "com.tencent.inputmethod",
        "com.jetbrains", "com.microsoft.VSCode", "com.visualstudio.code", "com.sublimetext", "com.sublimehq",
        "com.panic.Nova", "com.todesktop", "com.exafunction.windsurf",
        "com.anthropic.claude", "com.openai", "com.ollama", "com.lmstudio",
        "com.sequel-ace", "com.sequelpro", "com.dbeaver", "com.navicat", "com.mongodb.compass",
        "com.postmanlabs", "com.konghq.insomnia", "com.proxyman", "com.charlesproxy", "com.usebruno",
        "com.github.GitHubDesktop", "com.fork.Fork", "com.git-tower", "com.axosoft.gitkraken",
        "com.googlecode.iterm2", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "dev.warp",
        "com.tencent.xinWeChat", "com.tencent.qq", "com.tencent.WeWorkMac", "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams",
        "com.electron.lark", "notion.id", "md.obsidian", "com.evernote",
    ]

    static func isProtectedApp(_ name: String) -> Bool {
        for p in protectedAppPrefixes where name == p || name.hasPrefix(p + ".") { return true }
        return false
    }

    /// 缓存里无条件保护的子目录名。
    static let protectedCacheSubdirectories: Set<String> = ["CloudKit"]
}
