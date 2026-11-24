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

    private var hasPrimedCPU = false
    private var hasPrimedDisk = false
    private var hasPrimedNetwork = false

    /// 记录基线，让紧接着的第一次采样就有速度和 CPU 占用。
    /// 后台模式无需预热进程列表；面板打开时若已有近期进程基线也不重复全量扫描。
    func prime(includeProcesses: Bool = true) {
        if !hasPrimedCPU {
            cpu.prime()
            hasPrimedCPU = true
        }
        if !hasPrimedDisk {
            disk.prime()
            hasPrimedDisk = true
        }
        if !hasPrimedNetwork {
            network.prime()
            hasPrimedNetwork = true
        }
        if includeProcesses {
            let needsProcessPrime = lastProcessSample.map { Date().timeIntervalSince($0) > 25 } ?? true
            if needsProcessPrime {
                processes.prime()
            }
        }
    }

    /// 后台菜单栏模式下的按需预热：只初始化当前显示指标需要做差值的采样器。
    /// 返回是否刚建立新基线（需要短暂等待再采样才能算出差值）。
    func primeForMenuBar(_ metric: MenuBarMetric) -> Bool {
        switch metric {
        case .cpu:
            if !hasPrimedCPU {
                cpu.prime()
                hasPrimedCPU = true
                return true
            }
            return false
        case .network:
            if !hasPrimedNetwork {
                network.prime()
                hasPrimedNetwork = true
                return true
            }
            return false
        case .memory, .temperature, .none:
            return false
        }
    }

    /// 后台菜单栏轻量采样：只运行当前菜单栏指标对应的单个采样器，跳过磁盘/电池/功耗/端口/进程及其他传感器。
    func collectMenuBarValue(for metric: MenuBarMetric) -> MenuBarDisplayValue {
        switch metric {
        case .none:
            return .none
        case .cpu:
            let stats = cpu.sample()
            return .singleLine(metric: .cpu, text: PanelFormat.percent(stats.total))
        case .memory:
            let stats = memory.sample()
            return .singleLine(metric: .memory, text: PanelFormat.percent(stats.usedFraction))
        case .network:
            let stats = network.sample()
            let rates = MenuBarMetric.networkRates(for: stats)
            return .network(up: rates.up, down: rates.down)
        case .temperature:
            let temp = thermal.sampleCPUTemperatureOnly()
            return .singleLine(metric: .temperature, text: PanelFormat.temperature(temp))
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