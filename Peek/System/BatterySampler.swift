import Foundation
import IOKit
import IOKit.ps

/// 电池采集：电量、是否充电用 `IOPSCopyPowerSourcesInfo`，
/// 健康度、循环次数用 IOKit 的 `AppleSmartBattery` 属性。台式机没有电池时返回 nil。
struct BatterySampler {
    func sample() -> BatteryStats? {
        guard let powerSource = Self.powerSource() else { return nil }
        let smart = Self.smartBattery()
        return BatteryStats(
            level: powerSource.level,
            isCharging: powerSource.isCharging,
            health: smart?.health,
            cycleCount: smart?.cycleCount,
            timeRemainingMinutes: powerSource.timeRemainingMinutes,
            isPluggedIn: powerSource.isPluggedIn)
    }

    private static func powerSource() -> (
        level: Double, isCharging: Bool, isPluggedIn: Bool, timeRemainingMinutes: Int?
    )? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                // 只认内置电池，UPS 之类不算。
                description["Type"] as? String == "InternalBattery",
                let current = description["Current Capacity"] as? Int,
                let maximum = description["Max Capacity"] as? Int,
                maximum > 0
            else { continue }
            let level = min(1, max(0, Double(current) / Double(maximum)))
            let isCharging = description["Is Charging"] as? Bool ?? false
            let isPluggedIn = (description["Power Source State"] as? String) == "AC Power"
            let rawTime: Int? = if isCharging {
                description["Time to Full Charge"] as? Int
            } else {
                description["Time to Empty"] as? Int
            }
            // IOKit 未知剩余时间时会给 -1 或 0。
            let timeRemaining = rawTime.flatMap { $0 > 0 && $0 < 10_000 ? $0 : nil }
            return (level, isCharging, isPluggedIn, timeRemaining)
        }
        return nil
    }

    /// `MaxCapacity / DesignCapacity`。Apple Silicon 上的 DesignCapacity 常常读不到，
    /// 这时健康度为 nil。
    private static func smartBattery() -> (health: Double?, cycleCount: Int?)? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        func intProperty(_ key: String) -> Int? {
            let property = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0)
            return (property?.takeRetainedValue() as? NSNumber)?.intValue
        }

        var health: Double?
        if let max = intProperty("MaxCapacity"), let design = intProperty("DesignCapacity"),
            design > 0, max > 0
        {
            health = min(1, Double(max) / Double(design))
        }
        return (health, intProperty("CycleCount"))
    }
}