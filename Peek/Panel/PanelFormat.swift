import Foundation

/// 面板上数字的格式化。字节数按 Finder 的口径(十进制 GB)。
enum PanelFormat {
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    /// 内存容量按“关于本机”的口径（二进制 GB，取整），如 "48 GB"。
    /// 物理内存是 2 的幂，用十进制会显示成 51.54 GB，和系统口径对不上。
    static func gigabytes(_ bytes: UInt64) -> String {
        let gigabytes = (Double(bytes) / 1_073_741_824).rounded()
        return "\(Int(gigabytes)) GB"
    }

    /// 内存卡片底部用量，如 "10.8 GB / 16 GB"。
    static func memoryRatio(used: UInt64, total: UInt64) -> String {
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Int((Double(total) / 1_073_741_824).rounded())
        return String(format: "%.1f GB / %d GB", usedGB, totalGB)
    }

    /// 紧凑存储容量，如 "256GB"、"1.2TB"（十进制口径，与 Finder 一致）。
    static func compactStorage(_ bytes: UInt64) -> String {
        let tb = Double(bytes) / 1_000_000_000_000
        if tb >= 1 {
            let rounded = (tb * 10).rounded() / 10
            return rounded.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(rounded))TB"
                : String(format: "%.1fTB", rounded)
        }
        let gb = Int((Double(bytes) / 1_000_000_000).rounded())
        return "\(gb)GB"
    }

    /// 温度显示，如 "43°C"，读不到时返回 "--°C"。
    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "--°C" }
        return "\(Int(celsius.rounded()))°C"
    }

    /// 风扇转速显示，如 "1200 RPM"；无风扇机型返回 "Fanless"。
    static func fanRPM(_ thermal: ThermalStats) -> String {
        if let rpm = thermal.fanRPM {
            return "\(rpm) RPM"
        }
        if thermal.fanCount == 0 {
            return String(localized: "Fanless")
        }
        return "-- RPM"
    }

    /// 电池预计剩余时长，如 "21h"、"1h 20m"、"45m"。
    static func batteryTimeRemaining(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours >= 10 || mins == 0 {
            return "\(max(1, hours))h"
        }
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    /// 网速，如 "1.2 MB/s"。
    static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(max(0, bytesPerSecond))) + "/s"
    }

    // MARK: - 运行时长

    /// 运行时长的单位。分档规则见 `uptime(_:)`。
    enum UptimeUnit: Sendable, Equatable {
        case minutes, hours, days
    }

    /// 运行时长拆成数值和单位：不足 1 小时用分钟，不足 48 小时用小时，再长用天。
    struct Uptime: Sendable, Equatable {
        var amount: Int
        var unit: UptimeUnit
    }

    static func uptime(_ seconds: TimeInterval) -> Uptime {
        let total = max(0, seconds)
        if total < 3_600 {
            return Uptime(amount: Int(total / 60), unit: .minutes)
        }
        if total < 48 * 3_600 {
            return Uptime(amount: Int(total / 3_600), unit: .hours)
        }
        return Uptime(amount: Int(total / 86_400), unit: .days)
    }

    /// 本地化的运行时长，如 "Up 13h"、"已运行 13 小时"。
    /// `locale`、`bundle` 只给测试用，正常调用走当前语言。
    static func uptimeText(
        _ seconds: TimeInterval, locale: Locale = .current, bundle: Bundle = .main
    ) -> String {
        let uptime = uptime(seconds)
        let format: String.LocalizationValue = switch uptime.unit {
        case .minutes: "Up \(uptime.amount)m"
        case .hours: "Up \(uptime.amount)h"
        case .days: "Up \(uptime.amount)d"
        }
        return String(localized: format, bundle: bundle, locale: locale)
    }

    // MARK: - 电池

    /// 电量低于这个值（且没在充电）时，电池行用强调色。
    static let batteryAlertLevel: Double = 0.2

    static func batteryIsAlert(level: Double, isCharging: Bool) -> Bool {
        level < batteryAlertLevel && !isCharging
    }

    /// 电池状态文案。`BatteryStats` 只说得了“是否正在充电”，分不出“满电接着电源”，所以只有两种状态。
    /// `locale`、`bundle` 只给测试用，正常调用走当前语言。
    static func batteryStatusText(
        isCharging: Bool, locale: Locale = .current, bundle: Bundle = .main
    ) -> String {
        if isCharging {
            return String(localized: "Charging", bundle: bundle, locale: locale)
        }
        return String(localized: "On battery", bundle: bundle, locale: locale)
    }

    /// 电池行的补充说明，如 “Charging · Health 100% · 312 cycles”。读不到的段省略。
    static func batteryDetailText(
        _ battery: BatteryStats, locale: Locale = .current, bundle: Bundle = .main
    ) -> String {
        var parts = [
            batteryStatusText(isCharging: battery.isCharging, locale: locale, bundle: bundle)
        ]
        if let health = battery.health {
            parts.append(String(localized: "Health \(percent(health))", bundle: bundle, locale: locale))
        }
        if let cycles = battery.cycleCount {
            parts.append(String(localized: "\(cycles) cycles", bundle: bundle, locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 高占用进程

    /// 面板上列几个进程。
    static let topProcessCount = 3

    /// 按 CPU 降序取前几个，CPU 相同按内存降序（和 `ProcessSampler` 的排法一致）。
    static func topProcesses(
        _ processes: [ProcessUsage], limit: Int = PanelFormat.topProcessCount
    ) -> [ProcessUsage] {
        Array(
            processes.sorted { ($0.cpu, $0.memoryBytes) > ($1.cpu, $1.memoryBytes) }
                .prefix(max(0, limit)))
    }

    /// 按内存占用降序取前几个（供 MEM 卡片 Hover 详情展示）。
    static func topMemoryProcesses(
        _ processes: [ProcessUsage], limit: Int = PanelFormat.topProcessCount
    ) -> [ProcessUsage] {
        Array(
            processes.sorted { ($0.memoryBytes, $0.cpu) > ($1.memoryBytes, $1.cpu) }
                .prefix(max(0, limit)))
    }

    /// CPU 占用，单核满载 100%，多线程可以超过 100%（如 “230%”）。
    static func cpuPercent(_ cpu: Double) -> String {
        "\(Int((max(0, cpu) * 100).rounded()))%"
    }

    // MARK: - 趋势小图

    /// 网速趋势归一化时，分母至少是这个值（100 KB/s）。
    /// 网速常有几十 KB/s 的噪声，分母太小会把噪声放大成满格。
    static let minimumRateScale: Double = 100_000

    /// 把网速历史归一化到 0...1：分母取历史最大值，但不小于 `minimumScale`。
    static func normalizedRate(
        _ values: [Double], minimumScale: Double = PanelFormat.minimumRateScale
    ) -> [Double] {
        normalizedRates(values, [], minimumScale: minimumScale).0
    }

    /// 同时归一化下载、上传两条历史，**共用同一个分母**，这样两条线能直接比较长短。
    /// 分母取两条里的最大值，但不小于 `minimumScale`。两条长度不同也各按自己的长度归一化。
    static func normalizedRates(
        _ primary: [Double], _ secondary: [Double],
        minimumScale: Double = PanelFormat.minimumRateScale
    ) -> ([Double], [Double]) {
        let scale = max(primary.max() ?? 0, secondary.max() ?? 0, minimumScale)
        guard scale > 0 else {
            return (primary.map { _ in 0 }, secondary.map { _ in 0 })
        }
        func normalize(_ values: [Double]) -> [Double] {
            values.map { min(1, max(0, $0 / scale)) }
        }
        return (normalize(primary), normalize(secondary))
    }
}

/// 指标超过这些阈值时,面板对应卡片进入告警态。
enum MetricThreshold {
    static let cpu = 0.85
    static let memory = 0.80
    static let disk = 0.90
    static let thermalCelsius = 80.0
}
