import Foundation

/// 一次系统状态采样。所有字段都由系统接口得到，不需要额外权限。
/// 面板（PEEK-3）只读这个类型；采集实现见 PEEK-2。
struct SystemSnapshot: Sendable, Equatable {
    var timestamp: Date
    var cpu: CPUStats
    var memory: MemoryStats
    var disk: DiskStats
    var network: NetworkStats
    /// 台式机没有电池时为 nil。
    var battery: BatteryStats?
    /// 温度与风扇转速。
    var thermal: ThermalStats = .empty
    /// 整机实时功耗与电源适配器信息。
    var power: PowerStats = .empty
    /// 占用 CPU 最高的几个进程。
    var topProcesses: [ProcessUsage]
    /// 占用内存最高的几个进程。
    var topMemoryProcesses: [ProcessUsage] = []
    /// 已过滤的本机监听端口（开发服务 / AI / 数据库 / 代理）。
    var listeningPorts: [ListeningPort] = []
    /// 系统已开机时长（秒）。
    var uptime: TimeInterval
}

struct CPUStats: Sendable, Equatable {
    /// 总占用，0...1。
    var total: Double
    /// 每个核的占用，0...1。
    var perCore: [Double]
    /// 1、5、15 分钟平均负载。
    var load: [Double]
}

enum MemoryPressure: Int, Sendable, Equatable {
    case normal = 0
    case warning = 1
    case critical = 2
}

struct MemoryStats: Sendable, Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var pressure: MemoryPressure
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var appBytes: UInt64 = 0
    var wiredBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var cachedBytes: UInt64 = 0

    /// 已用比例，0...1。
    var usedFraction: Double {
        totalBytes == 0 ? 0 : min(1, Double(usedBytes) / Double(totalBytes))
    }
}

/// 磁盘空间五类分布（轻量估算，供面板分段条和像素矩阵展示）。
struct DiskBreakdown: Sendable, Equatable {
    var systemBytes: UInt64
    var appsBytes: UInt64
    var userBytes: UInt64
    var cacheBytes: UInt64
    var freeBytes: UInt64

    static let zero = DiskBreakdown(
        systemBytes: 0, appsBytes: 0, userBytes: 0, cacheBytes: 0, freeBytes: 0)

    var totalBytes: UInt64 {
        systemBytes + appsBytes + userBytes + cacheBytes + freeBytes
    }
}

struct DiskStats: Sendable, Equatable {
    /// 启动盘。
    var usedBytes: UInt64
    var totalBytes: UInt64
    /// 磁盘读写速度（字节/秒），只在独立窗口展示。
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var breakdown: DiskBreakdown = .zero

    var usedFraction: Double {
        totalBytes == 0 ? 0 : min(1, Double(usedBytes) / Double(totalBytes))
    }

    var freeFraction: Double { 1 - usedFraction }
    var freeBytes: UInt64 { totalBytes > usedBytes ? totalBytes - usedBytes : 0 }
}

struct ThermalStats: Sendable, Equatable {
    /// CPU / SoC 温度（摄氏度），读不到时为 nil。
    var temperatureCelsius: Double?
    /// GPU 温度（摄氏度），读不到时为 nil。
    var gpuTemperatureCelsius: Double? = nil
    /// SSD / NAND 温度（摄氏度），读不到时为 nil。
    var ssdTemperatureCelsius: Double? = nil
    /// 当前最高风扇转速（RPM），无风扇机型或读不到时为 nil。
    var fanRPM: Int?
    /// 物理风扇数量（MacBook Air 等无风扇机型为 0）。
    var fanCount: Int

    static let empty = ThermalStats(temperatureCelsius: nil, fanRPM: nil, fanCount: 0)
}

struct PowerStats: Sendable, Equatable {
    /// 整机实时功耗（瓦），读不到时为 nil。
    var systemWatts: Double?
    /// 外接电源实时输入功率（瓦）。
    var adapterInputWatts: Double?
    /// 接入电源适配器的额定功率（如 94W / 67W）。
    var adapterRatedWatts: Int?
    /// 电池净充/放电功率（瓦，正值为充电，负值为放电）。
    var batteryWatts: Double?
    /// 是否接通外接电源。
    var isExternalConnected: Bool
    /// 是否正在充电。
    var isCharging: Bool

    static let empty = PowerStats(
        systemWatts: nil,
        adapterInputWatts: nil,
        adapterRatedWatts: nil,
        batteryWatts: nil,
        isExternalConnected: false,
        isCharging: false
    )
}

struct NetworkStats: Sendable, Equatable {
    /// 默认网卡的下行、上行速度（字节/秒）。
    var downBytesPerSecond: Double
    var upBytesPerSecond: Double
}

struct BatteryStats: Sendable, Equatable {
    /// 电量，0...1。
    var level: Double
    var isCharging: Bool
    /// 健康度（当前最大容量 / 设计容量），0...1。读不到时为 nil。
    var health: Double?
    var cycleCount: Int?
    /// 预计剩余使用/充满时间（分钟），未知时为 nil。
    var timeRemainingMinutes: Int? = nil
    /// 是否接通交流电源。
    var isPluggedIn: Bool = false
}

struct ProcessUsage: Sendable, Equatable, Identifiable {
    var pid: Int32
    var name: String
    /// 单核满载算 1.0，多线程可超过 1。
    var cpu: Double
    var memoryBytes: UInt64

    var id: Int32 { pid }
}

extension SystemSnapshot {
    /// 预览和采集器还没就绪时的样例数据，对应设计稿里的数字。
    static let sample = SystemSnapshot(
        timestamp: Date(timeIntervalSince1970: 0),
        cpu: CPUStats(
            total: 0.32,
            perCore: [0.45, 0.38, 0.25, 0.28, 0.30, 0.22, 0.24, 0.62],
            load: [1.8, 1.6, 1.4]),
        memory: MemoryStats(
            usedBytes: 11_596_411_699, totalBytes: 16 << 30,
            pressure: .normal, swapUsedBytes: 512 << 20, swapTotalBytes: 2 << 30,
            appBytes: 5_400_000_000, wiredBytes: 2_800_000_000,
            compressedBytes: 3_396_411_699, cachedBytes: 2_200_000_000),
        disk: DiskStats(
            usedBytes: 256_000_000_000, totalBytes: 512_000_000_000,
            readBytesPerSecond: 142_000_000, writeBytesPerSecond: 68_000_000,
            breakdown: DiskBreakdown(
                systemBytes: 62_000_000_000,
                appsBytes: 58_000_000_000,
                userBytes: 98_000_000_000,
                cacheBytes: 38_000_000_000,
                freeBytes: 256_000_000_000)),
        network: NetworkStats(downBytesPerSecond: 12_400_000, upBytesPerSecond: 1_800_000),
        battery: BatteryStats(
            level: 0.94, isCharging: false, health: 0.98, cycleCount: 86,
            timeRemainingMinutes: 21 * 60, isPluggedIn: false),
        thermal: ThermalStats(
            temperatureCelsius: 43,
            gpuTemperatureCelsius: 41,
            ssdTemperatureCelsius: 36,
            fanRPM: 1200,
            fanCount: 1),
        power: PowerStats(
            systemWatts: 18.4,
            adapterInputWatts: 26.2,
            adapterRatedWatts: 96,
            batteryWatts: 7.8,
            isExternalConnected: true,
            isCharging: true),
        topProcesses: [
            ProcessUsage(pid: 101, name: "Xcode", cpu: 0.42, memoryBytes: 3_200_000_000),
            ProcessUsage(pid: 102, name: "Chrome", cpu: 0.28, memoryBytes: 2_400_000_000),
            ProcessUsage(pid: 103, name: "WindowServer", cpu: 0.16, memoryBytes: 980_000_000),
            ProcessUsage(pid: 104, name: "Cursor", cpu: 0.11, memoryBytes: 1_500_000_000),
            ProcessUsage(pid: 105, name: "Spotlight", cpu: 0.06, memoryBytes: 420_000_000),
        ],
        topMemoryProcesses: [
            ProcessUsage(pid: 101, name: "Xcode", cpu: 0.42, memoryBytes: 3_200_000_000),
            ProcessUsage(pid: 102, name: "Chrome", cpu: 0.28, memoryBytes: 2_400_000_000),
            ProcessUsage(pid: 104, name: "Cursor", cpu: 0.11, memoryBytes: 1_500_000_000),
            ProcessUsage(pid: 106, name: "Docker", cpu: 0.04, memoryBytes: 1_100_000_000),
            ProcessUsage(pid: 103, name: "WindowServer", cpu: 0.16, memoryBytes: 980_000_000),
        ],
        listeningPorts: [
            ListeningPort(port: 3000, pid: 1584, processName: "node", bindAddress: "127.0.0.1", category: .web),
            ListeningPort(port: 11434, pid: 1026, processName: "ollama", bindAddress: "127.0.0.1", category: .ai),
            ListeningPort(port: 5432, pid: 1037, processName: "postgres", bindAddress: "127.0.0.1", category: .database),
            ListeningPort(port: 7895, pid: 1034, processName: "mihomo", bindAddress: "127.0.0.1", category: .proxy),
        ],
        uptime: 3 * 86_400)
}
