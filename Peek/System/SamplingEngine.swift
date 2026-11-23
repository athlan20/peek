import Foundation

/// 一次采样的结果，从采样线程搬回主线程。
struct SamplingResult: Sendable {
    var snapshot: SystemSnapshot
    /// 最近 60 秒 CPU 总占用的时间加权平均，传给 `HealthScore.compute`。
    var cpuSustained: Double
}

/// 采集引擎。所有系统调用都在这个 actor 的后台执行器上跑，不占主线程；
/// `SystemMonitor` 只负责调度和把结果搬回主线程。
actor SamplingEngine {
    private var cpu = CPUSampler()
    private var memory = MemorySampler()
    private var disk = DiskSampler()
    private var network = NetworkSampler()
    private let battery = BatterySampler()
    private let thermal = ThermalSampler()
    private let power = PowerSampler()
    private let ports = PortSampler()
    private var processes = ProcessSampler()

    /// CPU 滑动平均的窗口（秒）。
    private static let sustainedWindow: TimeInterval = 60
    /// `(采样时间, 总占用)`。按时间窗口加权，而不是按样本数。
    private var cpuHistory: [(time: Date, total: Double)] = []

    /// 进程列表只在面板打开时采样，2 秒刷新一次让 CPU / MEM 进程方块形变更连贯流畅。
    private static let processInterval: TimeInterval = 2
    private var topProcesses: [ProcessUsage] = []
    private var topMemoryProcesses: [ProcessUsage] = []
    private var listeningPorts: [ListeningPort] = []
    private var lastProcessSample: Date?

    /// 记录基线，让紧接着的第一次采样就有速度和 CPU 占用。
    func prime() {
        cpu.prime()
        disk.prime()
        network.prime()
        processes.prime()
    }

    func collect(includeTopProcesses: Bool) -> SamplingResult {
        let now = Date()
        let cpuStats = cpu.sample()
        recordCPU(now: now, total: cpuStats.total)

        if includeTopProcesses, shouldUpdateProcesses(now: now) {
            let sampled = processes.sample()
            topProcesses = sampled.topCPU
            topMemoryProcesses = sampled.topMemory
            listeningPorts = ports.sample()
            lastProcessSample = now
        }

        let snapshot = SystemSnapshot(
            timestamp: now,
            cpu: cpuStats,
            memory: memory.sample(),
            disk: disk.sample(),
            network: network.sample(),
            battery: battery.sample(),
            thermal: thermal.sample(),
            power: power.sample(),
            topProcesses: topProcesses,
            topMemoryProcesses: topMemoryProcesses,
            listeningPorts: listeningPorts,
            uptime: ProcessInfo.processInfo.systemUptime)

        return SamplingResult(snapshot: snapshot, cpuSustained: sustainedCPU(now: now))
    }

    private func recordCPU(now: Date, total: Double) {
        cpuHistory.append((now, total))
        // 多留一个窗口，算窗口左边界时才有前一个样本可用。
        let cutoff = now.addingTimeInterval(-2 * Self.sustainedWindow)
        if let firstInRange = cpuHistory.firstIndex(where: { $0.time >= cutoff }) {
            cpuHistory.removeFirst(firstInRange)
        }
    }

    /// 时间加权平均：第 i 个样本代表它和前一个样本之间的这段时间。
    private func sustainedCPU(now: Date) -> Double {
        let start = now.addingTimeInterval(-Self.sustainedWindow)
        var weightedSum = 0.0
        var weight = 0.0
        for index in cpuHistory.indices where cpuHistory[index].time > start {
            let time = min(cpuHistory[index].time, now)
            let previousTime = index > 0 ? cpuHistory[index - 1].time : start
            let from = max(previousTime, start)
            guard time > from else { continue }
            weightedSum += cpuHistory[index].total * time.timeIntervalSince(from)
            weight += time.timeIntervalSince(from)
        }
        guard weight > 0 else { return cpuHistory.last?.total ?? 0 }
        return weightedSum / weight
    }

    private func shouldUpdateProcesses(now: Date) -> Bool {
        guard let lastProcessSample else { return true }
        return now.timeIntervalSince(lastProcessSample) >= Self.processInterval
    }
}