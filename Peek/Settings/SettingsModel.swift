import AppKit
import Foundation
import Observation
import ServiceManagement

/// 设置窗口的状态。设置值都经 `SettingsStore` 读写，这个类只管把结果搬到界面上。
@MainActor
@Observable
final class SettingsModel {
    private let store: SettingsStore

    private(set) var whitelist: [String]
    private(set) var projectRoots: [String]
    private(set) var refreshInterval: Int

    /// 完全磁盘访问。窗口出现和重新成为前台时刷新。
    private(set) var hasFullDiskAccess = false

    /// 开机启动。状态以 `SMAppService.mainApp.status` 为准。
    private(set) var launchAtLogin = false
    /// 注册或注销失败，开关下方显示一行说明。
    private(set) var launchAtLoginFailed = false

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.whitelist = store.whitelist
        self.projectRoots = store.projectRoots
        self.refreshInterval = store.refreshInterval
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - 白名单

    func addWhitelist() {
        let urls = Self.choose(allowsFiles: true)
        guard !urls.isEmpty else { return }
        store.addToWhitelist(urls.map(\.path))
        whitelist = store.whitelist
    }

    func removeWhitelist(_ path: String) {
        store.removeFromWhitelist(path)
        whitelist = store.whitelist
    }

    // MARK: - 项目扫描目录

    func addProjectRoot() {
        let urls = Self.choose(allowsFiles: false)
        guard !urls.isEmpty else { return }
        store.addProjectRoots(urls.map(\.path))
        projectRoots = store.projectRoots
    }

    func removeProjectRoot(_ path: String) {
        store.removeProjectRoot(path)
        projectRoots = store.projectRoots
    }

    // MARK: - 刷新间隔

    /// 存下来并立刻重启采样定时器，不需要重开面板。
    func setRefreshInterval(_ seconds: Int) {
        store.refreshInterval = seconds
        refreshInterval = store.refreshInterval
        SystemMonitor.shared.restartTimer()
    }

    // MARK: - 完全磁盘访问

    func reloadFullDiskAccess() {
        hasFullDiskAccess = CleanFS.probeFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 开机启动

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginFailed = false
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginFailed = true
        }
        // 开关状态始终跟着系统走；和用户点的目标不一致（失败、待用户确认）就提示。
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled { launchAtLoginFailed = true }
    }

    // MARK: - 选择文件

    private static func choose(allowsFiles: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = allowsFiles
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "Choose")
        return panel.runModal() == .OK ? panel.urls : []
    }
}