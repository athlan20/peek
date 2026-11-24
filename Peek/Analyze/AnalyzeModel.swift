import AppKit
import Foundation
import Observation

/// Analyze 窗口的状态：位置、逐层目录、Agent、下载。
///
/// "文件"和"Agent"两页各有一套逐层导航栈，切换页签不会打断另一页的扫描。扫描都在后台任务里做，界面只读结果。
///
/// 扫描可以停在检查点上，之后接着扫：
/// - 用户点暂停、离开正在扫的那一层（点进下一层、回上级、换位置）、关窗口，都是"停在检查点"。
///   检查点和已经量到的结果一起存进缓存，重启 Peek 后也在。
/// - 回到那一层、再打开窗口时自动接着扫；用户自己暂停的，在这次窗口里保持暂停，下次打开窗口自动继续。
/// - 只有点刷新才丢掉检查点从头扫。
@MainActor
@Observable
final class AnalyzeModel {
    enum Tab: String, CaseIterable, Identifiable {
        case items
        case agents
        case oldDownloads

        var id: String { rawValue }

        /// 能逐层进入、能切方块视图的页。
        var isBrowsable: Bool { self == .items || self == .agents }
    }

    /// 停下时的位置。
    enum Checkpoint: Sendable, Equatable {
        case directory(AnalyzeScanCheckpoint)
        case agents(AnalyzeAgentScan.Checkpoint)
    }

    /// 一层目录的扫描结果。栈里保留访问过的上级，返回时不用重扫。
    struct Listing {
        let url: URL
        var items: [AnalyzeItem] = []
        var totalBytes: UInt64 = 0
        var rootInaccessible = false
        /// 还没扫完（正在扫，或停在检查点上）。
        var isScanning = false
        /// 扫完的时间；没扫完时为 nil。
        var scannedAt: Date?
        /// 正在跑的那次扫描；nil 表示没在跑。
        var scanID: Int?
        /// 停下时的位置，接着扫用。
        var checkpoint: Checkpoint?
        /// 用户点了暂停：这次窗口里不自动接着扫。
        var pausedByUser = false
    }

    /// 一次正在跑的扫描。
    private struct Run {
        let target: Tab
        let gate: AnalyzePauseGate
        /// 结果不要了（点了刷新）：连检查点也不存。
        var discard = false
    }

    private enum Outcome: Sendable {
        case directory(AnalyzeScanResult)
        case agents(AnalyzeAgentScan.Result)
        case agent(AnalyzeAgentScan.Result, AnalyzeAgent)
    }

    /// 上次的扫描结果（含重启前的、扫到一半的），再打开时直接用，点刷新才重扫。不参与界面观察。
    @ObservationIgnored private var cache: AnalyzeCache
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let probeFullDiskAccess: @Sendable () -> Bool

    /// 是否已授予完全磁盘访问权限；首次打开 Analyze 时静默探测。
    private(set) var hasFullDiskAccess = true
    /// 用户主动选择“暂不授权，继续扫描”后放行（当前窗口会话内有效）。
    private var skippedFullDiskAccessGate = false

    /// 尚未获得完全磁盘访问权限且用户未选择跳过：先引导一次总授权，避免扫描时连环弹多个目录权限框。
    var needsFullDiskAccessPrompt: Bool {
        !hasFullDiskAccess && !skippedFullDiskAccessGate
    }

    init(
        cacheURL: URL = AnalyzeCache.defaultFileURL,
        probeFullDiskAccess: @escaping @Sendable () -> Bool = {
            CleanFS.probeFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser)
        }
    ) {
        self.cacheURL = cacheURL
        self.probeFullDiskAccess = probeFullDiskAccess
        cache = AnalyzeCache.load(from: cacheURL)
    }

    nonisolated static let homeURL = FileManager.default.homeDirectoryForCurrentUser
    nonisolated static let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    nonisolated static let startupDiskURL = URL(fileURLWithPath: "/", isDirectory: true)

    private var itemsStack: [Listing] = []
    private var agentsStack: [Listing] = []
    private(set) var oldDownloads: [AnalyzeItem] = []
    private var progressByTab: [Tab: AnalyzeScanProgress] = [:]

    var tab: Tab = .items {
        didSet {
            selection = nil
            guard !needsFullDiskAccessPrompt else { return }
            if tab == .agents {
                if agentsStack.isEmpty { openAgents() } else { resumeIfNeeded(.agents) }
            }
        }
    }

    /// 当前列表选中的条目 URL。
    var selection: URL?
    /// 等待二次确认移到废纸篓的条目。
    var pendingTrash: AnalyzeItem?
    /// 移到废纸篓失败的提示。
    var errorMessage: String?

    @ObservationIgnored private var runs: [Int: Run] = [:]
    @ObservationIgnored private var nextScanID = 1
    /// 窗口开着。关着时停下的扫描不自动接着扫。
    @ObservationIgnored private var isActive = false

    private var oldDownloadsTask: Task<[AnalyzeItem], Never>?
    private var oldDownloadsToken = 0
    /// 旧下载扫完过一次（或从缓存读到了）。
    private var oldDownloadsLoaded = false
    private var oldDownloadsScannedAt: Date?

    /// 当前页的导航栈；"下载"页沿用"文件"页的。最后一个就是当前目录。
    var stack: [Listing] { tab == .agents ? agentsStack : itemsStack }
    var currentURL: URL? { stack.last?.url }
    var canGoBack: Bool { tab.isBrowsable && stack.count > 1 }
    var isScanning: Bool { stack.last?.isScanning ?? false }
    /// 当前这一层被用户暂停了。
    var isPaused: Bool { isScanning && stack.last?.pausedByUser == true }
    var items: [AnalyzeItem] { stack.last?.items ?? [] }
    var totalBytes: UInt64 { stack.last?.totalBytes ?? 0 }
    var rootInaccessible: Bool { stack.last?.rootInaccessible ?? false }
    /// 当前页的结果是什么时候扫的；没扫完或没有结果时为 nil。
    var scannedAt: Date? { tab == .oldDownloads ? oldDownloadsScannedAt : stack.last?.scannedAt }
    /// "下载"页正在扫。
    var isScanningDownloads: Bool { oldDownloadsTask != nil }
    var progress: AnalyzeScanProgress { progressByTab[browsableTab] ?? AnalyzeScanProgress() }
    /// 当前页能刷新。
    var canRefresh: Bool {
        tab.isBrowsable ? !stack.isEmpty : (oldDownloadsLoaded && oldDownloadsTask == nil)
    }

    var visibleItems: [AnalyzeItem] {
        switch tab {
        case .items, .agents: items
        case .oldDownloads: oldDownloads
        }
    }

    var selectedItem: AnalyzeItem? {
        guard let selection else { return nil }
        return visibleItems.first { $0.url == selection }
    }

    /// "下载"页沿用"文件"页的导航。
    private var browsableTab: Tab { tab == .agents ? .agents : .items }

    // MARK: - 生命周期与导航

    /// 窗口出现时调用。先静默检测完全磁盘访问权限：未授权时先展示引导页，不立刻触发多目录系统弹窗。
    func start() {
        isActive = true
        hasFullDiskAccess = probeFullDiskAccess()
        guard !needsFullDiskAccessPrompt else { return }
        beginScanning()
    }

    /// App 重新回到前台时重检完全磁盘访问权限；一旦授权成功，自动开始扫描。
    func recheckFullDiskAccess() {
        let wasPrompting = needsFullDiskAccessPrompt
        hasFullDiskAccess = probeFullDiskAccess()
        if wasPrompting, hasFullDiskAccess, isActive {
            beginScanning()
        }
    }

    /// 打开系统设置 → 隐私与安全性 → 完全磁盘访问权限。
    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 用户选择暂不授予完全磁盘访问权限，直接开始扫描（可能会触发系统的逐目录授权弹窗）。
    func continueWithoutFullDiskAccess() {
        skippedFullDiskAccessGate = true
        if isActive {
            beginScanning()
        }
    }

    private func beginScanning() {
        if itemsStack.isEmpty {
            open(Self.homeURL)
        } else {
            mutateLast(.items) { $0.pausedByUser = false }
            resumeIfNeeded(.items)
        }
        if tab == .agents {
            if agentsStack.isEmpty {
                openAgents()
            } else {
                mutateLast(.agents) { $0.pausedByUser = false }
                resumeIfNeeded(.agents)
            }
        }
        if !oldDownloadsLoaded { refreshOldDownloads() }
    }

    /// 窗口关闭时调用：所有扫描停在检查点上（存进缓存），不在后台继续读盘。
    func stop() {
        isActive = false
        for id in runs.keys { runs[id]?.gate.requestStop() }
        oldDownloadsTask?.cancel()
        oldDownloadsTask = nil
        oldDownloadsToken &+= 1
        selection = nil
        pendingTrash = nil
    }

    /// 暂停或继续当前这一层。暂停就是停在检查点上（存进缓存），继续从检查点接着扫。
    func togglePause() {
        let target = browsableTab
        guard let last = (target == .agents ? agentsStack : itemsStack).last, last.isScanning else { return }
        if last.pausedByUser {
            mutateLast(target) { $0.pausedByUser = false }
            // 还没停稳的，停稳后会自动接着扫。
            resumeIfNeeded(target)
        } else {
            mutateLast(target) { $0.pausedByUser = true }
            if let id = last.scanID { runs[id]?.gate.requestStop() }
        }
    }

    /// 从"选择位置"打开一个位置，总是在"文件"页里看。
    func open(_ url: URL) {
        if tab != .items { tab = .items }
        selection = nil
        stopRuns(in: itemsStack)
        itemsStack = [cachedListing(for: url) ?? Listing(url: url, isScanning: true)]
        resumeIfNeeded(.items)
    }

    /// 刷新当前页：丢掉当前这一层的结果和检查点，从头扫（"下载"页重扫下载）。上级不动。
    func refresh() {
        selection = nil
        guard tab.isBrowsable else {
            refreshOldDownloads(force: true)
            return
        }
        let target = tab
        guard let last = stack.last else { return }
        if let id = last.scanID {
            runs[id]?.discard = true
            runs[id]?.gate.requestStop()
        }
        mutateLast(target) { listing in
            listing = Listing(url: listing.url, isScanning: true)
        }
        if last.url == AnalyzeAgentScan.rootURL {
            cache.agentsPartial = nil
        }
        launch(target)
    }

    private func cachedListing(for url: URL) -> Listing? {
        guard let cached = cache.listing(for: url) else { return nil }
        var listing = Listing(
            url: url, items: cached.items, totalBytes: cached.totalBytes,
            rootInaccessible: cached.rootInaccessible)
        if let checkpoint = cached.checkpoint {
            listing.isScanning = true
            listing.checkpoint = .directory(checkpoint)
        } else {
            listing.scannedAt = cached.scannedAt
        }
        return listing
    }

    func enter(_ item: AnalyzeItem) {
        guard item.isDirectory, !item.isInaccessible else { return }
        let target = browsableTab
        selection = nil

        // Agent 页第一层点进某个 Agent：它的目录已经量好，直接列出来，不用再扫。
        if let agentID = AnalyzeAgentScan.agentID(from: item.url) {
            // 还在量的时候各目录的数还没出来，先不让进。
            guard target == .agents, agentsStack.first?.isScanning == false else { return }
            let paths = agentPaths[agentID] ?? []
            agentsStack.append(Listing(
                url: item.url,
                items: paths,
                totalBytes: paths.reduce(UInt64(0)) { $0 &+ $1.size },
                scannedAt: agentsStack.first?.scannedAt))
            return
        }

        // 正在扫的这一层停在检查点上，回来时接着扫。
        if let last = (target == .agents ? agentsStack : itemsStack).last { stopRuns(in: [last]) }
        mutateStack(target) { $0.append(cachedListing(for: item.url) ?? Listing(url: item.url, isScanning: true)) }
        resumeIfNeeded(target)
    }

    func goBack() {
        navigate(to: stack.count - 2)
    }

    /// 点面包屑回到第 `index` 层。
    func navigate(to index: Int) {
        guard tab.isBrowsable, stack.indices.contains(index), index < stack.count - 1 else { return }
        let target = browsableTab
        // 离开的几层停在检查点上（存进缓存），以后再进来接着扫。
        stopRuns(in: Array(stack[(index + 1)...]))
        mutateStack(target) { $0.removeSubrange((index + 1)...) }
        selection = nil
        resumeIfNeeded(target)
    }

    /// 当前层没扫完、没在扫、用户也没暂停时，从检查点（没有就从头）接着扫。
    private func resumeIfNeeded(_ target: Tab) {
        guard
            let last = (target == .agents ? agentsStack : itemsStack).last,
            last.isScanning, last.scanID == nil, !last.pausedByUser
        else { return }
        launch(target)
    }

    /// 任意文件夹。
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.text("Choose")
        panel.directoryURL = currentURL?.isFileURL == true ? currentURL : Self.homeURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    // MARK: - Agent 页

    /// 每个 Agent 量好的目录（第二层的条目），键是 Agent id。
    private var agentPaths: [String: [AnalyzeItem]] = [:]

    /// 第一层：有上次量完的结果就直接用；上次量到一半的接着量；都没有就从头量。
    private func openAgents() {
        if let partial = cache.agentsPartial {
            agentPaths = partial.checkpoint.paths
            agentsStack = [Listing(
                url: AnalyzeAgentScan.rootURL,
                items: partial.items,
                totalBytes: partial.items.reduce(UInt64(0)) { $0 &+ $1.size },
                isScanning: true,
                checkpoint: .agents(partial.checkpoint))]
        } else if let cached = cache.agents {
            agentPaths = cached.paths
            agentsStack = [Listing(
                url: AnalyzeAgentScan.rootURL,
                items: cached.agents,
                totalBytes: cached.agents.reduce(UInt64(0)) { $0 &+ $1.size },
                scannedAt: cached.scannedAt)]
        } else {
            agentsStack = [Listing(url: AnalyzeAgentScan.rootURL, isScanning: true)]
        }
        resumeIfNeeded(.agents)
    }

    // MARK: - 扫描

    /// 扫当前这一层：从它的检查点接着扫，没有就从头扫。
    private func launch(_ target: Tab) {
        guard let listing = (target == .agents ? agentsStack : itemsStack).last else { return }
        let url = listing.url
        let id = nextScanID
        nextScanID += 1
        let gate = AnalyzePauseGate()
        runs[id] = Run(target: target, gate: gate)
        mutateLast(target) { listing in
            listing.scanID = id
            listing.isScanning = true
            listing.pausedByUser = false
            listing.scannedAt = nil
        }
        progressByTab[target] = Self.progress(of: listing.checkpoint)

        let progressHandler: @Sendable (AnalyzeScanProgress) -> Void = { [weak self] value in
            Task { @MainActor in self?.applyProgress(value, scanID: id) }
        }
        let shouldStop: @Sendable () -> Bool = { gate.shouldStop() }
        let home = Self.homeURL
        let work: Task<Outcome, Never>
        if url == AnalyzeAgentScan.rootURL {
            var resume: AnalyzeAgentScan.Checkpoint?
            if case .agents(let checkpoint)? = listing.checkpoint { resume = checkpoint }
            work = Task.detached(priority: .userInitiated) {
                .agents(AnalyzeAgentScan.scan(
                    home: home, resume: resume, progress: progressHandler, isCancelled: shouldStop))
            }
        } else if let agentID = AnalyzeAgentScan.agentID(from: url) {
            guard let agent = AnalyzeClassifier.agents.first(where: { $0.id == agentID }) else { return }
            var resume: AnalyzeAgentScan.Checkpoint?
            if case .agents(let checkpoint)? = listing.checkpoint { resume = checkpoint }
            // 这一层列的是目录，扫描给的快照是第一层的 Agent 块，用不上。
            let stripped: @Sendable (AnalyzeScanProgress) -> Void = { value in
                var value = value
                value.items = nil
                progressHandler(value)
            }
            work = Task.detached(priority: .userInitiated) {
                .agent(
                    AnalyzeAgentScan.scan(
                        home: home, agents: [agent], resume: resume, progress: stripped, isCancelled: shouldStop),
                    agent)
            }
        } else {
            var resume: AnalyzeScanCheckpoint?
            if case .directory(let checkpoint)? = listing.checkpoint { resume = checkpoint }
            work = Task.detached(priority: .userInitiated) {
                .directory(AnalyzeScanner.scan(
                    root: url, resume: resume, progress: progressHandler, isCancelled: shouldStop))
            }
        }
        // 强引用 self：窗口关了也要等扫描停稳，把检查点存下来。
        Task {
            let outcome = await work.value
            self.finish(outcome, scanID: id, url: url)
        }
    }

    private static func progress(of checkpoint: Checkpoint?) -> AnalyzeScanProgress {
        switch checkpoint {
        case .directory(let value)?:
            AnalyzeScanProgress(scannedBytes: value.scannedBytes, itemCount: value.itemCount)
        case .agents(let value)?:
            AnalyzeScanProgress(scannedBytes: value.scannedBytes, itemCount: value.itemCount)
        case nil:
            AnalyzeScanProgress()
        }
    }

    /// 一次扫描结束（扫完，或停在检查点上）。这一层可能已经不在栈里了，结果照样进缓存。
    private func finish(_ outcome: Outcome, scanID id: Int, url: URL) {
        guard let run = runs.removeValue(forKey: id) else { return }
        let target = run.target
        let index = (target == .agents ? agentsStack : itemsStack).lastIndex { $0.scanID == id }
        func update(_ body: (inout Listing) -> Void) {
            guard let index else { return }
            mutateStack(target) { body(&$0[index]) }
        }
        guard !run.discard else {
            update { $0.scanID = nil }
            return
        }
        let now = Date()

        switch outcome {
        case .directory(let result):
            if result.wasCancelled {
                guard let checkpoint = result.checkpoint else {
                    update { $0.scanID = nil }
                    return
                }
                var shown = checkpoint.finished
                update { listing in
                    listing.scanID = nil
                    listing.checkpoint = .directory(checkpoint)
                    shown = listing.items
                }
                cache.store(
                    AnalyzeCache.Listing(
                        items: shown, totalBytes: shown.reduce(UInt64(0)) { $0 &+ $1.size },
                        rootInaccessible: false, scannedAt: now, checkpoint: checkpoint),
                    for: url)
            } else {
                update { listing in
                    listing.items = result.items
                    listing.totalBytes = result.totalBytes
                    listing.rootInaccessible = result.rootInaccessible
                    listing.isScanning = false
                    listing.scannedAt = now
                    listing.scanID = nil
                    listing.checkpoint = nil
                }
                cache.store(
                    AnalyzeCache.Listing(
                        items: result.items, totalBytes: result.totalBytes,
                        rootInaccessible: result.rootInaccessible, scannedAt: now),
                    for: url)
                if index == (target == .agents ? agentsStack : itemsStack).indices.last {
                    progressByTab[target] = AnalyzeScanProgress(
                        scannedBytes: result.totalBytes, itemCount: result.items.count)
                }
            }

        case .agents(let result):
            if result.wasCancelled {
                guard let checkpoint = result.checkpoint else {
                    update { $0.scanID = nil }
                    return
                }
                var shown = checkpoint.agents
                update { listing in
                    listing.scanID = nil
                    listing.checkpoint = .agents(checkpoint)
                    shown = listing.items
                }
                cache.agentsPartial = AnalyzeCache.AgentsPartial(items: shown, checkpoint: checkpoint)
            } else {
                agentPaths = result.paths
                update { listing in
                    listing.items = result.agents
                    listing.totalBytes = result.agents.reduce(UInt64(0)) { $0 &+ $1.size }
                    listing.isScanning = false
                    listing.scannedAt = now
                    listing.scanID = nil
                    listing.checkpoint = nil
                }
                cache.agents = AnalyzeCache.Agents(agents: result.agents, paths: result.paths, scannedAt: now)
                cache.agentsPartial = nil
                progressByTab[.agents] = AnalyzeScanProgress(
                    scannedBytes: result.agents.reduce(UInt64(0)) { $0 &+ $1.size }, itemCount: result.agents.count)
            }

        case .agent(let result, let agent):
            if result.wasCancelled {
                // 只重量一个 Agent 时停下的位置只记在内存里。
                update { listing in
                    listing.scanID = nil
                    listing.checkpoint = result.checkpoint.map { .agents($0) }
                }
            } else {
                applyAgentRefresh(result, agent: agent, update: update)
            }
        }
        persist()
        // 离开后又回到这一层、点了继续但还没停稳的：现在接着扫。
        if isActive, let index, index == (target == .agents ? agentsStack : itemsStack).indices.last {
            resumeIfNeeded(target)
        }
    }

    /// 在某个 Agent 的目录列表里刷新：只重量这一个 Agent，第一层它的块跟着更新。
    private func applyAgentRefresh(
        _ result: AnalyzeAgentScan.Result, agent: AnalyzeAgent, update: ((inout Listing) -> Void) -> Void
    ) {
        let paths = result.paths[agent.id] ?? []
        agentPaths[agent.id] = paths.isEmpty ? nil : paths
        let total = paths.reduce(UInt64(0)) { $0 &+ $1.size }
        update { listing in
            listing.items = paths
            listing.totalBytes = total
            listing.isScanning = false
            listing.scannedAt = Date()
            listing.scanID = nil
            listing.checkpoint = nil
        }
        guard !agentsStack.isEmpty, !agentsStack[0].isScanning else { return }
        // 第一层这个 Agent 的块换成新量的大小（量出来是 0 就去掉）。
        let agentURL = AnalyzeAgentScan.url(for: agent)
        var roots = agentsStack[0].items.filter { $0.url != agentURL } + result.agents
        roots.sort { $0.size > $1.size }
        agentsStack[0].items = roots
        agentsStack[0].totalBytes = roots.reduce(UInt64(0)) { $0 &+ $1.size }
        cache.agents = AnalyzeCache.Agents(
            agents: roots, paths: agentPaths, scannedAt: agentsStack[0].scannedAt ?? Date())
        progressByTab[.agents] = AnalyzeScanProgress(scannedBytes: total, itemCount: paths.count)
    }

    /// 进度带着中途快照时，直接替换那一层的条目，方块边扫边长。
    private func applyProgress(_ value: AnalyzeScanProgress, scanID id: Int) {
        guard let run = runs[id], !run.discard else { return }
        let target = run.target
        let stack = target == .agents ? agentsStack : itemsStack
        guard let index = stack.lastIndex(where: { $0.scanID == id }) else { return }
        if index == stack.count - 1 { progressByTab[target] = value }
        guard let partial = value.items else { return }
        let sorted = partial.sorted { lhs, rhs in
            lhs.size == rhs.size ? lhs.name < rhs.name : lhs.size > rhs.size
        }
        mutateStack(target) { stack in
            stack[index].items = sorted
            stack[index].totalBytes = sorted.reduce(UInt64(0)) { $0 &+ $1.size }
        }
    }

    /// 让这些层正在跑的扫描停在检查点上。
    private func stopRuns(in listings: [Listing]) {
        for listing in listings {
            if let id = listing.scanID { runs[id]?.gate.requestStop() }
        }
    }

    private func mutateStack(_ target: Tab, _ body: (inout [Listing]) -> Void) {
        if target == .agents { body(&agentsStack) } else { body(&itemsStack) }
    }

    private func mutateLast(_ target: Tab, _ body: (inout Listing) -> Void) {
        mutateStack(target) { stack in
            guard !stack.isEmpty else { return }
            body(&stack[stack.count - 1])
        }
    }

    /// 缓存写盘放后台，连着几次改动只写最后一次。
    private func persist() {
        saveTask?.cancel()
        let snapshot = cache
        let url = cacheURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            snapshot.save(to: url)
        }
    }

    /// 旧下载固定看 `~/Downloads`，和当前选的位置无关。有上次的结果就直接用，`force` 时重扫。
    private func refreshOldDownloads(force: Bool = false) {
        if !force, let cached = cache.downloads {
            oldDownloads = cached.items
            oldDownloadsScannedAt = cached.scannedAt
            oldDownloadsLoaded = true
            return
        }
        oldDownloadsTask?.cancel()
        oldDownloadsToken &+= 1
        let token = oldDownloadsToken

        let task = Task.detached(priority: .utility) {
            AnalyzeScanner.oldDownloads(isCancelled: { Task.isCancelled })
        }
        oldDownloadsTask = task

        Task { [weak self] in
            let items = await task.value
            guard let self, token == self.oldDownloadsToken else { return }
            let now = Date()
            self.oldDownloads = items
            self.oldDownloadsScannedAt = now
            self.oldDownloadsLoaded = true
            self.oldDownloadsTask = nil
            self.cache.downloads = AnalyzeCache.Downloads(items: items, scannedAt: now)
            self.persist()
        }
    }

    // MARK: - 操作

    func revealSelected() {
        guard let item = selectedItem else { return }
        reveal(item)
    }

    func requestTrashSelected() {
        guard let item = selectedItem else { return }
        requestTrash(item)
    }

    /// 条目在磁盘上对应的文件夹：普通条目就是它自己；Agent 页第一层的 Agent 块是它量到的各个目录
    /// （还没量完时为空）。
    func directories(of item: AnalyzeItem) -> [AnalyzeItem] {
        if let agentID = AnalyzeAgentScan.agentID(from: item.url) {
            return agentPaths[agentID] ?? []
        }
        return item.url.isFileURL ? [item] : []
    }

    /// 右键菜单"在访达中显示"。Agent 块一次选中它的所有目录。
    func reveal(_ item: AnalyzeItem) {
        let urls = directories(of: item).map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// 右键菜单"删除…"：选中它，走和底部按钮一样的二次确认，确认后移到废纸篓。
    func requestTrash(_ item: AnalyzeItem) {
        guard !directories(of: item).isEmpty else { return }
        selection = item.url
        pendingTrash = item
    }

    /// 二次确认后执行。只移到废纸篓，可以直接从废纸篓恢复。Agent 块会把它的目录逐个移走。
    func confirmTrash() {
        guard let item = pendingTrash else { return }
        pendingTrash = nil
        var failed = false
        for directory in directories(of: item) {
            do {
                try FileManager.default.trashItem(at: directory.url, resultingItemURL: nil)
                forget(directory)
            } catch {
                failed = true
            }
        }
        // Agent 块的目录都移走了，块本身也去掉。
        if let agentID = AnalyzeAgentScan.agentID(from: item.url), agentPaths[agentID]?.isEmpty != false {
            mutateStack(.agents) { stack in
                for index in stack.indices { stack[index].items.removeAll { $0.url == item.url } }
            }
            cache.agents?.agents.removeAll { $0.url == item.url }
            persist()
            if selection == item.url { selection = nil }
        }
        if failed {
            errorMessage = L10n.text("Couldn’t move the item to the Trash.")
        }
    }

    /// 从各个列表里去掉已经移走的条目，并把包含它的条目和上级目录的总量减掉（两页都要改）。
    private func forget(_ item: AnalyzeItem) {
        let url = item.url
        let childPrefix = url.path + "/"
        let home = Self.homeURL

        /// 一层列表：去掉它本身，包含它的条目缩小；列表总量在它属于这一层时减掉。
        func prune(_ items: inout [AnalyzeItem]) -> Bool {
            var touched = false
            items = items.compactMap { entry in
                if entry.url == url {
                    touched = true
                    return nil
                }
                guard Self.covers(entry, url, home: home) else { return entry }
                touched = true
                return AnalyzeItem(
                    url: entry.url, name: entry.name, isDirectory: entry.isDirectory,
                    size: Self.subtract(entry.size, item.size), isInaccessible: entry.isInaccessible)
            }
            return touched
        }

        for target in [Tab.items, .agents] {
            mutateStack(target) { stack in
                for index in stack.indices {
                    // 停在检查点上的层：检查点里记的也去掉，接着扫时才不会把它算回来。
                    if case .directory(var checkpoint)? = stack[index].checkpoint {
                        checkpoint.forget(item)
                        stack[index].checkpoint = .directory(checkpoint)
                    }
                    let touched = prune(&stack[index].items)
                    if touched || Self.isDescendant(url, of: stack[index].url) {
                        stack[index].totalBytes = Self.subtract(stack[index].totalBytes, item.size)
                    }
                }
            }
        }
        for key in agentPaths.keys {
            _ = prune(&agentPaths[key, default: []])
        }
        // 缓存里的也改掉，免得下次打开又看到已经删掉的东西。
        cache.forget(item)
        if var agents = cache.agents {
            _ = prune(&agents.agents)
            for key in agents.paths.keys { _ = prune(&agents.paths[key, default: []]) }
            cache.agents = agents
        }
        persist()
        oldDownloads.removeAll { $0.url == url || $0.url.path.hasPrefix(childPrefix) }
        if selection == url { selection = nil }
    }

    /// `entry` 是否包含 `url`：普通文件夹看路径；Agent 页第一层的 Agent 块看 `url` 是不是这个 Agent 的。
    private static func covers(_ entry: AnalyzeItem, _ url: URL, home: URL) -> Bool {
        if let agentID = AnalyzeAgentScan.agentID(from: entry.url) {
            return AnalyzeClassifier.agent(for: url, home: home)?.id == agentID
        }
        return isDescendant(url, of: entry.url)
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        guard directory.isFileURL else { return false }
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return url.path.hasPrefix(prefix)
    }

    private static func subtract(_ total: UInt64, _ size: UInt64) -> UInt64 {
        total > size ? total - size : 0
    }
}

/// 扫描的停止开关。扫描器每处理一个条目问一次 `shouldStop()`，要停时扫描停在检查点上返回。
final class AnalyzePauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopRequested: Bool { lock.withLock { stopped } }

    func requestStop() {
        lock.withLock { stopped = true }
    }

    /// 在扫描任务里调用：要停了，或任务被取消了。
    func shouldStop() -> Bool {
        isStopRequested || Task.isCancelled
    }
}
