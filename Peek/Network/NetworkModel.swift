import AppKit
import Foundation
import Observation

/// Network 端口独立窗口的状态模型：管理端口采样、搜索筛选、剪贴板复制与安全终止进程。
@MainActor
@Observable
final class NetworkModel {
    private(set) var ports: [ListeningPort]
    private(set) var isRefreshing = false

    var search = ""
    var selectedCategory: PortCategory?
    var selectedPortID: String?

    /// 刚刚复制成功的端口 ID，用于底部按钮短暂展示「已复制」反馈。
    private(set) var copiedPortID: String?

    /// 待确认终止的端口记录。
    var pendingKillPort: ListeningPort?
    var confirmingKill = false

    /// 终止进程失败时的提示信息。
    var errorMessage: String?
    var showingError = false

    private let sampler = PortSampler()
    private var refreshTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?

    init(initialPorts: [ListeningPort] = SystemMonitor.shared.snapshot.listeningPorts) {
        self.ports = initialPorts
    }

    // MARK: - 派生视图数据

    var filteredPorts: [ListeningPort] {
        NetworkPortGroups.filter(ports, query: search, category: selectedCategory)
    }

    var groups: [NetworkProcessGroup] {
        NetworkPortGroups.groupByProcess(filteredPorts)
    }

    var selectedPort: ListeningPort? {
        guard let selectedPortID else { return nil }
        return filteredPorts.first { $0.id == selectedPortID }
            ?? ports.first { $0.id == selectedPortID }
    }

    var pendingKillAffectedPorts: [ListeningPort] {
        guard let pendingKillPort else { return [] }
        return NetworkPortGroups.portsSharingPID(pendingKillPort.pid, in: ports)
    }

    func count(for category: PortCategory) -> Int {
        ports.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
    }

    // MARK: - 定时刷新

    func startAutoRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performRefresh()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.performRefresh()
        }
    }

    private func performRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let sampler = self.sampler
        let sampled = await Task.detached(priority: .utility) {
            sampler.sample()
        }.value
        guard !Task.isCancelled else {
            isRefreshing = false
            return
        }
        ports = sampled
        if let selectedPortID, !sampled.contains(where: { $0.id == selectedPortID }) {
            self.selectedPortID = nil
        }
        isRefreshing = false
    }

    // MARK: - 端口操作

    func openInBrowser(_ item: ListeningPort) {
        guard item.isWebOpenable,
              let url = URL(string: "http://localhost:\(item.port)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func copyAddress(_ item: ListeningPort) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.copyableAddress, forType: .string)

        copiedPortID = item.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            if self?.copiedPortID == item.id {
                self?.copiedPortID = nil
            }
        }
    }

    func revealExecutable(_ item: ListeningPort) {
        guard let path = item.executablePath, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func requestKill(_ item: ListeningPort) {
        pendingKillPort = item
        confirmingKill = true
    }

    func confirmKill() {
        guard let target = pendingKillPort else { return }
        pendingKillPort = nil
        let outcome = PortProcessTerminator.terminate(pid: target.pid)
        switch outcome {
        case .terminated, .alreadyExited:
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                await self?.performRefresh()
                SystemMonitor.shared.refreshNow()
            }
        case .permissionDenied:
            errorMessage = L10n.text("Permission denied to stop this process. It may belong to another user or require elevated privileges.")
            showingError = true
        case .protectedProcess:
            errorMessage = L10n.text("This process is protected and cannot be terminated from Peek.")
            showingError = true
        case .failed(let code):
            errorMessage = String(cString: strerror(code))
            showingError = true
        }
    }
}
