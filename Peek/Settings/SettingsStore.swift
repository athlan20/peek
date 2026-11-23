import Foundation

/// 设置窗口里所有设置项的读写，和界面无关。
///
/// 全部存在 `UserDefaults`，key 已定，重启后保留：
/// - `clean.whitelist`：清理白名单（绝对路径），`CleanModel` 扫描时读它。
/// - `clean.projectRoots`：项目构建产物的扫描目录（绝对路径），留空用默认目录（R7）。
/// - `refreshIntervalSeconds`：面板打开时的采样间隔，`SystemMonitor` 读它。
/// - `app.language`：界面语言（`system` / `en` / `zh-Hans`），默认跟随系统。
/// - `app.appearance`：界面外观（`system` / `light` / `dark`），默认跟随系统。
///
/// `UserDefaults` 可注入，测试里用临时 suite。
struct SettingsStore {
    static let whitelistKey = "clean.whitelist"
    static let projectRootsKey = "clean.projectRoots"
    static let refreshIntervalKey = "refreshIntervalSeconds"
    static let appLanguageKey = "app.language"
    static let appAppearanceKey = "app.appearance"

    /// 面板打开时可选的采样间隔（秒）。第一项是默认值。
    static let refreshIntervalOptions = [1, 2, 5]

    var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 路径列表（白名单、扫描目录共用）

    /// 规范化并去重，保留第一次出现的顺序。规范化失败（相对路径、含 `..` 等）的项丢掉。
    static func normalizedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            guard let normalized = CleanGuard.normalized(path), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    func paths(forKey key: String) -> [String] {
        Self.normalizedPaths(defaults.stringArray(forKey: key) ?? [])
    }

    func setPaths(_ paths: [String], forKey key: String) {
        defaults.set(Self.normalizedPaths(paths), forKey: key)
    }

    // MARK: - 白名单

    var whitelist: [String] {
        paths(forKey: Self.whitelistKey)
    }

    /// 追加。规范化失败或已存在的不重复加。
    func addToWhitelist(_ paths: [String]) {
        setPaths(whitelist + paths, forKey: Self.whitelistKey)
    }

    func removeFromWhitelist(_ path: String) {
        setPaths(whitelist.filter { $0 != path }, forKey: Self.whitelistKey)
    }

    // MARK: - 项目扫描目录

    var projectRoots: [String] {
        paths(forKey: Self.projectRootsKey)
    }

    /// 追加。规范化失败或已存在的不重复加。
    func addProjectRoots(_ paths: [String]) {
        setPaths(projectRoots + paths, forKey: Self.projectRootsKey)
    }

    func removeProjectRoot(_ path: String) {
        setPaths(projectRoots.filter { $0 != path }, forKey: Self.projectRootsKey)
    }

    // MARK: - 刷新间隔

    /// 没有、不是整数或不在选项里时用 1 秒。
    static func refreshInterval(from defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: refreshIntervalKey)
        return refreshIntervalOptions.contains(value) ? value : refreshIntervalOptions[0]
    }

    /// 读到无效值时回退到默认，写入时也收敛到选项里。
    var refreshInterval: Int {
        get { Self.refreshInterval(from: defaults) }
        nonmutating set {
            let value = Self.refreshIntervalOptions.contains(newValue) ? newValue : Self.refreshIntervalOptions[0]
            defaults.set(value, forKey: Self.refreshIntervalKey)
        }
    }

    // MARK: - 界面语言

    /// 没有或不是有效语言值时回退到跟随系统。
    nonisolated static func appLanguage(from defaults: UserDefaults) -> AppLanguage {
        guard let raw = defaults.string(forKey: appLanguageKey),
              let language = AppLanguage(rawValue: raw)
        else { return .system }
        return language
    }

    var appLanguage: AppLanguage {
        get { Self.appLanguage(from: defaults) }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.appLanguageKey)
        }
    }

    // MARK: - 界面外观

    /// 没有或不是有效外观值时回退到跟随系统。
    nonisolated static func appAppearance(from defaults: UserDefaults) -> AppAppearance {
        guard let raw = defaults.string(forKey: appAppearanceKey),
              let appearance = AppAppearance(rawValue: raw)
        else { return .system }
        return appearance
    }

    var appAppearance: AppAppearance {
        get { Self.appAppearance(from: defaults) }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.appAppearanceKey)
        }
    }
}