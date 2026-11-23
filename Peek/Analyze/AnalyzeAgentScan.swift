import Foundation

/// Analyze 的"Agent"页：按 `AnalyzeClassifier.agents` 表量出每个 AI Agent 的目录占用。
///
/// 第一层每个 Agent 是一个虚拟条目（URL 形如 `peek-agent://claude`，不对应磁盘上的路径），
/// 大小是它所有目录之和；点进去是它在磁盘上的各个目录（真实路径），再往里就是普通的逐层分析。
/// 规格见 `docs/analyze-treemap.md`。
enum AnalyzeAgentScan {
    static let scheme = "peek-agent"
    /// 第一层（所有 Agent）的虚拟 URL。
    static let rootURL = URL(string: "\(scheme)://all")!

    /// 某个 Agent 的虚拟 URL。
    static func url(for agent: AnalyzeAgent) -> URL {
        URL(string: "\(scheme)://\(agent.id)")!
    }

    /// 虚拟 URL 对应的 Agent id；第一层根和普通文件路径返回 nil。
    static func agentID(from url: URL) -> String? {
        guard url.scheme == scheme, let host = url.host, host != "all" else { return nil }
        return host
    }

    struct Result: Sendable {
        /// 第一层：每个找到目录的 Agent 一个条目，按大小从大到小。
        var agents: [AnalyzeItem] = []
        /// 第二层：每个 Agent 的目录，键是 Agent id，按大小从大到小。
        var paths: [String: [AnalyzeItem]] = [:]
        var wasCancelled = false
        /// 取消时量到的位置，交给下一次 `scan(resume:)` 接着量。
        var checkpoint: Checkpoint?
    }

    /// 量到一半停下时的位置，可以存盘。
    struct Checkpoint: Codable, Sendable, Equatable {
        /// 量完的 Agent（含量出来是 0、不列出的）。
        var doneAgentIDs: [String] = []
        var agents: [AnalyzeItem] = []
        var paths: [String: [AnalyzeItem]] = [:]
        /// 正在量的 Agent、它量完的目录（相对主目录）和对应的行。
        var agentID: String?
        var donePaths: [String] = []
        var rows: [AnalyzeItem] = []
        /// 正在量的那个目录和它里面的进度。
        var currentPath: String?
        var inner: AnalyzeScanCheckpoint?
        var scannedBytes: UInt64 = 0
        var itemCount = 0
    }

    /// 依次量每个 Agent 的每个目录。同步执行，调用方放在后台任务里。
    /// 不存在的目录跳过；量出来是 0 的 Agent 不列。`resume` 是上次停下的位置。
    static func scan(
        home: URL,
        agents: [AnalyzeAgent] = AnalyzeClassifier.agents,
        resume: Checkpoint? = nil,
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (AnalyzeScanProgress) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> Result {
        var result = Result()
        var state = resume ?? Checkpoint()
        result.agents = state.agents
        result.paths = state.paths

        func stop(_ inner: AnalyzeScanCheckpoint?, path: String?) -> Result {
            state.agents = result.agents
            state.paths = result.paths
            state.currentPath = path
            state.inner = inner
            result.wasCancelled = true
            result.checkpoint = state
            return result
        }

        for agent in agents where !state.doneAgentIDs.contains(agent.id) {
            if state.agentID != agent.id {
                state.agentID = agent.id
                state.donePaths = []
                state.rows = []
            }
            for path in agent.paths where !state.donePaths.contains(path) {
                let inner = state.currentPath == path ? state.inner : nil
                if isCancelled() { return stop(inner, path: inner == nil ? nil : path) }
                let url = home.appendingPathComponent(path, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    state.donePaths.append(path)
                    continue
                }
                let base = (state.scannedBytes, state.itemCount)
                // 中途快照：量完的 Agent + 正在量的这个（已量完的目录 + 这个目录目前量到的）。
                let doneAgents = result.agents
                let agentSoFar = state.rows.reduce(UInt64(0)) { $0 &+ $1.size }
                let agentURL = Self.url(for: agent)
                let agentName = agent.name
                let measured = AnalyzeScanner.scan(
                    root: url,
                    resume: inner,
                    progress: { value in
                        let current = agentSoFar &+ value.scannedBytes
                        let items = current > 0
                            ? doneAgents + [AnalyzeItem(
                                url: agentURL, name: agentName, isDirectory: true,
                                size: current, isInaccessible: false)]
                            : doneAgents
                        progress(AnalyzeScanProgress(
                            scannedBytes: base.0 &+ value.scannedBytes,
                            itemCount: base.1 + value.itemCount,
                            items: items))
                    },
                    isCancelled: isCancelled)
                if measured.wasCancelled { return stop(measured.checkpoint, path: path) }
                state.scannedBytes &+= measured.totalBytes
                state.itemCount += measured.items.count
                state.donePaths.append(path)
                state.currentPath = nil
                state.inner = nil
                state.rows.append(AnalyzeItem(
                    url: url,
                    name: "~/" + path,
                    isDirectory: true,
                    size: measured.totalBytes,
                    isInaccessible: measured.rootInaccessible))
            }
            var rows = state.rows
            rows.sort { $0.size > $1.size }
            let total = rows.reduce(UInt64(0)) { $0 &+ $1.size }
            state.doneAgentIDs.append(agent.id)
            state.agentID = nil
            state.donePaths = []
            state.rows = []
            guard total > 0 else { continue }
            result.paths[agent.id] = rows
            result.agents.append(AnalyzeItem(
                url: Self.url(for: agent),
                name: agent.name,
                isDirectory: true,
                size: total,
                isInaccessible: false))
        }
        result.agents.sort { $0.size > $1.size }
        return result
    }
}
