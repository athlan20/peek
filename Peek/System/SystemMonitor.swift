import Foundation
import Observation

/// 采样频率。面板打开时按设置间隔采样；关闭后若菜单栏显示实时指标则沿用设置间隔，仅图标时 30 秒低频采样。
enum SamplingMode: Sendable {
    case panelOpen
    case background

    /// 两次采样的间隔。
    fileprivate var interval: Duration {
        switch self {
        case .panelOpen:
            .seconds(SettingsStore.refreshInterval(from: .standard))
        case .background:
            SettingsStore.menuBarMetric(from: .standard) == .none
                ? .seconds(30)
                : .seconds(SettingsStore.refreshInterval(from: .standard))
        }
    }
}

/// 系统状态的唯一数据源。面板和菜单栏只读 `snapshot`。
///
/// 采样全部在 `SamplingEngine`（actor，后台线程）里做，这里只负责定时和把结果搬回主线程。
@MainActor
@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()

    private(set) var snapshot: SystemSnapshot = .sample

    private var cpuSamples = SampleHistory()
    private var memorySamples = SampleHistory()
    private var networkDownSamples = SampleHistory()
    private var networkUpSamples = SampleHistory()
    private var thermalSamples = SampleHistory(capacity: 30)
    private var powerSamples = SampleHistory(capacity: 24)
    private var diskReadSamples = SampleHistory(capacity: 30)
    private var diskWriteSamples = SampleHistory(capacity: 30)
    private var coreHistories: [SampleHistory] = []

    /// 面板打开期间最近 60 个样本的趋势历史，0...1。后台采样不追加，只存内存。
    var cpuHistory: [Double] { cpuSamples.values }
    var memoryHistory: [Double] { memorySamples.values }
    /// 下行速度历史，单位字节/秒。面板按历史最大值归一化后再画。
    var networkDownHistory: [Double] { networkDownSamples.values }
    /// 上行速度历史，单位字节/秒。和下行共用同一个分母归一化。
    var networkUpHistory: [Double] { networkUpSamples.values }
    /// 温度历史（摄氏度），供热力点阵展示。
    var thermalHistory: [Double] { thermalSamples.values }
    /// 整机实时功耗历史（瓦），供功耗柱状时间轴展示。
    var powerHistory: [Double] { powerSamples.values }
    /// 磁盘读取速率历史（字节/秒）。
    var diskReadHistory: [Double] { diskReadSamples.values }
    /// 磁盘写入速率历史（字节/秒）。
    var diskWriteHistory: [Double] { diskWriteSamples.values }
    /// 每核近期占用历史（0...1），每个核心最多保留 20 个样本。
    var perCoreHistory: [[Double]] { coreHistories.map(\.values) }

    private let engine = SamplingEngine()
    private var mode: SamplingMode = .background
    private var samplingTask: Task<Void, Never>?

    /// 切换采样频率。面板出现时传 `.panelOpen`，消失时传 `.background`。
    /// 切到同一模式不做任何事，避免重启定时器。
    func setMode(_ mode: SamplingMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        start()
    }

    /// 刷新间隔或菜单栏指标改了之后重启定时器，新的间隔立刻生效。
    func restartTimer() {
        start()
    }

    /// 立即触发一次采样（供面板底部刷新按钮调用）。
    func refreshNow() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.engine.collect(includeTopProcesses: self.mode == .panelOpen)
            self.snapshot = result.snapshot
            if self.mode == .panelOpen {
                self.recordHistory(for: result.snapshot)
            }
        }
    }

    /// 默认 `.background`，初始化后立刻采一次，菜单栏马上有数据。
    private init() {
        start()
    }

    private func start() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            await self?.run()
        }
    }

    /// 采样循环。取消时（切换模式）立刻退出，不发布过期结果。
    private func run() async {
        await engine.prime(includeProcesses: mode == .panelOpen)
        // 留一点时间让 tick / 字节计数产生差值，第一次采样才有意义。
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }

        while !Task.isCancelled {
            let includeTopProcesses = mode == .panelOpen
            let result = await engine.collect(includeTopProcesses: includeTopProcesses)
            if Task.isCancelled { return }

            snapshot = result.snapshot
            // 只有面板打开时才记历史：后台采样会把时间轴拉乱。
            if mode == .panelOpen {
                recordHistory(for: result.snapshot)
            }

            do { try await Task.sleep(for: mode.interval) } catch { return }
        }
    }

    private func recordHistory(for snapshot: SystemSnapshot) {
        cpuSamples.append(snapshot.cpu.total)
        memorySamples.append(snapshot.memory.usedFraction)
        networkDownSamples.append(snapshot.network.downBytesPerSecond)
        networkUpSamples.append(snapshot.network.upBytesPerSecond)
        if let temp = snapshot.thermal.temperatureCelsius {
            thermalSamples.append(temp)
        }
        if let watts = snapshot.power.systemWatts {
            powerSamples.append(watts)
        }
        diskReadSamples.append(snapshot.disk.readBytesPerSecond)
        diskWriteSamples.append(snapshot.disk.writeBytesPerSecond)
        let cores = snapshot.cpu.perCore
        if coreHistories.count != cores.count {
            coreHistories = Array(repeating: SampleHistory(capacity: 20), count: cores.count)
        }
        for (index, value) in cores.enumerated() {
            coreHistories[index].append(value)
        }
    }

    /// 预览和离屏渲染用：直接灌一批样例历史，只影响当前实例。
    func seedHistory(
        cpu: [Double], memory: [Double], networkDown: [Double], networkUp: [Double] = [],
        thermal: [Double] = [], power: [Double] = [],
        diskRead: [Double] = [], diskWrite: [Double] = []
    ) {
        cpuSamples = SampleHistory(values: cpu)
        memorySamples = SampleHistory(values: memory)
        networkDownSamples = SampleHistory(values: networkDown)
        networkUpSamples = SampleHistory(values: networkUp)
        thermalSamples = SampleHistory(capacity: 30, values: thermal)
        powerSamples = SampleHistory(capacity: 24, values: power)
        diskReadSamples = SampleHistory(capacity: 30, values: diskRead)
        diskWriteSamples = SampleHistory(capacity: 30, values: diskWrite)
    }

    /// 预览和离屏渲染用：直接换一份快照（含电池、高占用进程），只影响当前实例。
    /// 下一次采样会把它覆盖掉，所以只适合瞬时渲染。
    func seedSnapshot(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
    }
}