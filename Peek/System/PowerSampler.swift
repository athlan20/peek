import Foundation
import IOKit

/// 整机实时功耗与电源适配器采集：纯本地 IOKit 只读 `AppleSmartBattery`（零管理员权限、零联网）。
/// 按需单键读取属性，避免每秒调用 `IORegistryEntryCreateCFProperties` 整棵序列化上百个无关字段。
struct PowerSampler {
    func sample() -> PowerStats {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return .empty }
        defer { IOObjectRelease(service) }

        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        let isExternal = (prop("ExternalConnected") as? Bool) ?? false
        let isCharging = (prop("IsCharging") as? Bool) ?? false

        // 1. 电源适配器额定功率（仅外接电源时读取，如 94W / 67W / 140W）。
        var adapterRatedWatts: Int?
        if isExternal,
            let adapter = prop("AdapterDetails") as? [String: Any],
            let watts = Self.intValue(adapter["Watts"]), watts > 0
        {
            adapterRatedWatts = watts
        }

        // 2. 实时系统功耗与输入功率（Apple Silicon `PowerTelemetryData` 单位均为 mW）。
        var systemWatts: Double?
        var adapterInputWatts: Double?
        var batteryWatts: Double?

        if let telemetry = prop("PowerTelemetryData") as? [String: Any] {
            if let sysLoadMW = Self.doubleValue(telemetry["SystemLoad"]), sysLoadMW > 0 {
                systemWatts = sysLoadMW / 1000.0
            }
            if let powerInMW = Self.doubleValue(telemetry["SystemPowerIn"]), powerInMW >= 0 {
                adapterInputWatts = powerInMW / 1000.0
            }
            if let batPowerMW = Self.signedInt64Value(telemetry["BatteryPower"]) {
                batteryWatts = Double(batPowerMW) / 1000.0
            }
        }

        // 3. Intel Mac 或无 `PowerTelemetryData` 时，用电池瞬时电压 × 电流（mV × mA）估算功耗。
        if systemWatts == nil {
            if let voltageMV = Self.doubleValue(prop("Voltage")),
                let ampMA = Self.signedInt64Value(prop("InstantAmperage"))
                    ?? Self.signedInt64Value(prop("Amperage"))
            {
                let watts = (voltageMV * Double(ampMA)) / 1_000_000.0
                if batteryWatts == nil {
                    batteryWatts = watts
                }
                if !isExternal, watts < 0 {
                    systemWatts = abs(watts)
                }
            }
        }

        return PowerStats(
            systemWatts: systemWatts,
            adapterInputWatts: isExternal ? adapterInputWatts : nil,
            adapterRatedWatts: isExternal ? adapterRatedWatts : nil,
            batteryWatts: batteryWatts,
            isExternalConnected: isExternal,
            isCharging: isCharging
        )
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    /// IORegistry 的有符号 64 位整数（例如放电时的负电流/负功率）有时以无符号 bitPattern 暴露。
    private static func signedInt64Value(_ any: Any?) -> Int64? {
        guard let n = any as? NSNumber else { return nil }
        let raw = n.uint64Value
        return Int64(bitPattern: raw)
    }
}
