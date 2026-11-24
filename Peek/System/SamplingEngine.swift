import Foundation

/// 一次采样的结果，从采样线程搬回主线程。
struct SamplingResult: Sendable {
    var snapshot: SystemSnapshot
}

/// 采集引擎。所有系统调用都在这个 actor 的后台执行器上跑，不占主线程；
/// `SystemMonitor` 只负责调度和把结果搬回主线程。
actor SamplingEngine {
    private var cpu = CPUSampler()
    private var memory = MemorySampler()
    private var disk = DiskSampler()
    private var network = NetworkSampler()
    private let battery = BatterySampler()
    private var thermal = ThermalSampler()
    private let power = PowerSampler()
    private let ports = PortSampler()
    private var processes = ProcessSampler()

    /// 进程列表只在面板打开时采样，2 秒刷新一次让 CPU / MEM 进程方块形变更连贯流畅。
    private static let processInterval: TimeInterval = 2
    /// 监听端口列表变化较慢，5 秒刷新一次即可，减少遍历全进程 FD 的系统调用开销。
    private static let portInterval: TimeInterval = 5
    private var topProcesses: [ProcessUsage] = []
    private var topMemoryProcesses: [ProcessUsage] = []
    private var listeningPorts: [ListeningPort] = []
    private var lastProcessSample: Date?
    private var lastPortSample: Date?

    private var hasPrimedBase = false

    /// 记录基线，让紧接着的第一次采样就有速度和 CPU 占用。
    /// 后台模式无需预热进程列表；面板打开时若已有近期进程基线也不重复全量扫描。
    func prime(includeProcesses: Bool = true) {
        if !hasPrimedBase {
            cpu.prime()
            disk.prime()
            network.prime()
            hasPrimedBase = true
        }
        if includeProcesses {
            let needsProcessPrime = lastProcessSample.map { Date().timeIntervalSince($0) > 25 } ?? true
            if needsProcessPrime {
                processes.prime()
            }
        }
    }

    func collect(includeTopProcesses: Bool) -> SamplingResult {
        let now = Date()
        let cpuStats = cpu.sample()

        if includeTopProcesses {
            if shouldUpdateProcesses(now: now) {
                let sampled = processes.sample()
                topProcesses = sampled.topCPU
                topMemoryProcesses = sampled.topMemory
                lastProcessSample = now
            }
            if shouldUpdatePorts(now: now) {
                listeningPorts = ports.sample()
                lastPortSample = now
            }
        }

        let snapshot = SystemSnapshot(
            timestamp: now,
            cpu: cpuStats,
            memory: memory.sample(),
            disk: disk.sample(includeBreakdown: includeTopProcesses),
            network: network.sample(),
            battery: battery.sample(),
            thermal: thermal.sample(),
            power: power.sample(),
            topProcesses: topProcesses,
            topMemoryProcesses: topMemoryProcesses,
            listeningPorts: listeningPorts,
            uptime: ProcessInfo.processInfo.systemUptime)

        return SamplingResult(snapshot: snapshot)
    }

    private func shouldUpdateProcesses(now: Date) -> Bool {
        guard let lastProcessSample else { return true }
        return now.timeIntervalSince(lastProcessSample) >= Self.processInterval
    }

    private func shouldUpdatePorts(now: Date) -> Bool {
        guard let lastPortSample else { return true }
        return now.timeIntervalSince(lastPortSample) >= Self.portInterval
    }
}