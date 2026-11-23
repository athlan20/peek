import AppKit
import Foundation
import Observation

/// 后台逐个量 App 大小的暂停状态机。和磁盘、界面无关,单独单元测试。
struct UninstallMeasureState: Equatable, Sendable {
    /// 用户按了暂停。
    private(set) var isPaused = false

    /// 还有 App 没量完才需要暂停;都量完了按钮就不出现。
    static func canPause(pendingCount: Int) -> Bool { pendingCount > 0 }

    /// 暂停 / 继续。没有待量的 App 时什么也不做。
    mutating func toggle(pendingCount: Int) {
        guard Self.canPause(pendingCount: pendingCount) else { return }
        isPaused.toggle()
    }

    /// 从头开始量时清掉暂停。
    mutating func resume() {
        isPaused = false
    }
}

/// Uninstall 窗口：App 列表 → 选中后预览残留 → 确认卸载 → 结果。
@MainActor
@Observable
final class UninstallModel {
    enum SortKey: String, CaseIterable, Identifiable {
        case name, size, lastUsed
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case list, previewing, uninstalling, done
    }

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    var search = ""
    var sortKey: SortKey = .name

    private(set) var phase: Phase = .list
    private(set) var current: InstalledApp?
    private(set) var residuals: [ResidualItem] = []
    private(set) var isFindingResiduals = false
    var selectedResiduals: Set<String> = []
    var confirming = false
    private(set) var outcome: UninstallOutcome?

    private var loadToken = 0
    private var findToken = 0

    /// 量大小的暂停状态。
    private(set) var measure = UninstallMeasureState()

    /// 用户暂停了后台量大小。
    var isPaused: Bool { measure.isPaused }

    /// 还有几个 App 没量出大小。
    var pendingCount: Int { apps.reduce(0) { $0 + ($1.bytes == nil ? 1 : 0) } }

    /// 还有 App 正在量大小,顶部的暂停 / 继续按钮要出现。
    var isMeasuring: Bool { pendingCount > 0 }

    private var whitelist: [String] { UserDefaults.standard.stringArray(forKey: "clean.whitelist") ?? [] }

    // MARK: - 列表

    var visibleApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
        }
        switch sortKey {
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            return filtered.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        case .lastUsed:
            return filtered.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        loadToken &+= 1
        let token = loadToken
        let context = UninstallContext.live(whitelist: whitelist)

        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) { AppCatalog.list(context: context) }.value
            // 列表回来时窗口已经关了(模型释放),或者刷新过,就到此为止。
            guard self?.loadToken == token else { return }
            self?.apps = list
            self?.isLoading = false
            // 大小和最后使用时间在后台逐个补，补一个刷新一个。
            for app in list {
                let result = await Task.detached(priority: .utility) { () -> (UInt64, Date?) in
                    var measure = CleanMeasure()
                    return (measure.measure(app.url).bytes, AppCatalog.lastUsedDate(of: app.url))
                }.value
                // 每轮重新取一次弱引用:模型释放后循环就结束,
                // 不会把整个模型一直强留到量完。
                guard let model = self, token == model.loadToken else { return }
                // 量的过程中这个 App 已经被卸载(从列表里去掉了):跳过它,接着量剩下的。
                if let index = model.apps.firstIndex(where: { $0.id == app.id }) {
                    model.apps[index].bytes = result.0
                    model.apps[index].lastUsed = result.1
                }
                // 暂停:量完当前这个 App 后停住,接着量剩下的。
                // 每 200ms 看一次标志,不做忙等;模型释放或刷新时直接退出。
                while true {
                    guard let paused = self?.measure.isPaused, self?.loadToken == token else { return }
                    if !paused { break }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    /// 暂停 / 继续后台量大小。没有 App 没量完时按钮不出现,也不做事。
    func togglePause() {
        measure.toggle(pendingCount: pendingCount)
    }

    func reload() {
        loadToken &+= 1
        isLoading = false
        // 刷新从头量,用户暂停过也一起清掉。
        measure.resume()
        load()
    }

    // MARK: - 预览

    func preview(_ app: InstalledApp) {
        guard app.blocked == nil else { return }
        current = app
        residuals = []
        selectedResiduals = []
        outcome = nil
        phase = .previewing
        isFindingResiduals = true
        findToken &+= 1
        let token = findToken
        let context = UninstallContext.live(whitelist: whitelist)
        let all = apps

        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                ResidualFinder.find(for: app, installed: all, context: context)
            }.value
            guard let self, token == self.findToken else { return }
            self.residuals = found
            self.selectedResiduals = Set(found.filter(\.defaultSelected).map(\.id))
            self.isFindingResiduals = false
        }
    }

    func backToList() {
        findToken &+= 1
        phase = .list
        current = nil
        residuals = []
    }

    var selectedItems: [ResidualItem] { residuals.filter { selectedResiduals.contains($0.id) } }
    var selectedBytes: UInt64 { selectedItems.reduce(current?.bytes ?? 0) { $0 &+ $1.bytes } }
    var includesPersonalData: Bool { selectedItems.contains { $0.category == .personalData } }

    func setSelected(_ on: Bool, _ item: ResidualItem) {
        if on { selectedResiduals.insert(item.id) } else { selectedResiduals.remove(item.id) }
    }

    // MARK: - 执行

    func requestUninstall() {
        guard phase == .previewing, current != nil, !isFindingResiduals else { return }
        confirming = true
    }

    func confirmedUninstall() {
        confirming = false
        guard let app = current else { return }
        let items = selectedItems
        phase = .uninstalling
        let context = UninstallContext.live(whitelist: whitelist)

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                UninstallExecutor(context: context).uninstall(app, residuals: items)
            }.value
            guard let self else { return }
            self.outcome = result
            self.phase = .done
            if result.appRemoved {
                HistoryStore.shared.record(HistoryEntry(
                    kind: .uninstall, itemCount: result.processed, freedBytes: result.freedBytes,
                    failedCount: result.failed, note: app.name))
                self.apps.removeAll { $0.id == app.id }
            }
        }
    }

    func finish() {
        phase = .list
        current = nil
        residuals = []
        outcome = nil
    }
}
