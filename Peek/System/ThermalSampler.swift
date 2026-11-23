import Darwin
import Foundation
import IOKit

/// 温度与风扇转速采集：优先通过 IOKit 的 `AppleSMC` 读取 CPU / GPU / SSD 温度和风扇转速，
/// Apple Silicon 上若某类 SMC 温度键读不到，再回退到 IOHID 温度传感器。
/// 无风扇机型（如 MacBook Air）或读不到时返回 nil，由面板优雅降级展示。
struct ThermalSampler {
    func sample() -> ThermalStats {
        var cpuTemp: Double?
        var gpuTemp: Double?
        var ssdTemp: Double?
        var fanRPM: Int?
        var fanCount = 0

        if let smc = SMCConnection() {
            defer { smc.close() }
            let fans = smc.readFans()
            fanCount = fans.count
            fanRPM = fans.rpm
            cpuTemp = smc.readCPUTemperature()
            gpuTemp = smc.readGPUTemperature()
            ssdTemp = smc.readSSDTemperature()
        }

        if cpuTemp == nil || gpuTemp == nil || ssdTemp == nil {
            let hid = IOHIDThermalReader.readTemperatures()
            if cpuTemp == nil { cpuTemp = hid.cpu }
            if gpuTemp == nil { gpuTemp = hid.gpu }
            if ssdTemp == nil { ssdTemp = hid.ssd }
        }

        return ThermalStats(
            temperatureCelsius: cpuTemp,
            gpuTemperatureCelsius: gpuTemp,
            ssdTemperatureCelsius: ssdTemp,
            fanRPM: fanRPM,
            fanCount: fanCount)
    }
}

// MARK: - AppleSMC（纯只读）

private struct SMCConnection {
    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            return nil
        }
        self.connection = conn
    }

    func close() {
        IOServiceClose(connection)
    }

    func readFans() -> (count: Int, rpm: Int?) {
        guard let countValue = readDouble(key: "FNum") else {
            return (0, nil)
        }
        let count = max(0, min(8, Int(countValue.rounded())))
        guard count > 0 else { return (0, nil) }

        var maxRPM: Double?
        for index in 0..<count {
            if let rpm = readDouble(key: "F\(index)Ac"), rpm >= 0, rpm < 20_000 {
                maxRPM = max(maxRPM ?? 0, rpm)
            }
        }
        return (count, maxRPM.map { Int($0.rounded()) })
    }

    func readCPUTemperature() -> Double? {
        // 兼容 Apple Silicon（M1/M2/M3/M4 系列）与 Intel Mac 常见 CPU 温度键。
        readAverageTemperature(keys: [
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P",
            "Tp0X", "Tp0b", "Tp0f", "Tp0j",
            "Tc0a", "Tc0b", "TC0P", "TC0D", "TC0E", "TC0F", "TC0C", "TC1C",
        ])
    }

    func readGPUTemperature() -> Double? {
        // 兼容 Apple Silicon（Tg*）与 Intel Mac（TG*）GPU 温度键。
        readAverageTemperature(keys: [
            "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
            "Tg04", "Tg0C", "Tg0K", "Tg0S", "Tg1b", "Tg1p", "Tg0P",
            "TG0D", "TG0P", "TG0E", "TG0F",
        ])
    }

    func readSSDTemperature() -> Double? {
        // 兼容 Apple Silicon NAND（TH*）与 Intel SSD（TN*）温度键。
        readAverageTemperature(keys: [
            "TH0a", "TH0b", "TH0c", "TH0x", "TH1a", "TH1b",
            "TN0D", "TN0P", "TN0H",
        ])
    }

    private func readAverageTemperature(keys: [String]) -> Double? {
        var readings: [Double] = []
        for key in keys {
            if let value = readDouble(key: key), (10.0...120.0).contains(value) {
                readings.append(value)
            }
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    private func readDouble(key: String) -> Double? {
        guard let fourCC = Self.fourCharCode(key) else { return nil }

        // 第一步：查询键的 dataSize 和 dataType（selector 9 = kSMCGetKeyInfo）。
        var infoInput = SMCKeyData()
        infoInput.key = fourCC
        infoInput.data8 = 9
        guard let infoOutput = call(input: infoInput) else { return nil }

        let dataSize = infoOutput.keyInfo.dataSize
        let dataType = infoOutput.keyInfo.dataType
        guard dataSize > 0, dataSize <= 32 else { return nil }

        // 第二步：读取键的原始字节（selector 5 = kSMCReadKey）。
        var readInput = SMCKeyData()
        readInput.key = fourCC
        readInput.keyInfo.dataSize = dataSize
        readInput.data8 = 5
        guard let readOutput = call(input: readInput) else { return nil }

        let bytes = readOutput.bytesArray
        return Self.decode(bytes: bytes, size: Int(dataSize), type: dataType)
    }

    private func call(input: SMCKeyData) -> SMCKeyData? {
        var inputCopy = input
        var output = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            2, // kSMCHandleYPCEvent
            &inputCopy,
            inputSize,
            &output,
            &outputSize)
        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    private static func fourCharCode(_ string: String) -> UInt32? {
        let utf8 = Array(string.utf8)
        guard utf8.count == 4 else { return nil }
        return (UInt32(utf8[0]) << 24)
            | (UInt32(utf8[1]) << 16)
            | (UInt32(utf8[2]) << 8)
            | UInt32(utf8[3])
    }

    private static func decode(bytes: [UInt8], size: Int, type: UInt32) -> Double? {
        guard size <= bytes.count else { return nil }
        switch type {
        case fourCharCode("ui8 "):
            guard size >= 1 else { return nil }
            return Double(bytes[0])
        case fourCharCode("ui16"):
            guard size >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case fourCharCode("sp78"):
            guard size >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case fourCharCode("fpe2"):
            guard size >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case fourCharCode("flt "):
            guard size >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Float(bitPattern: bits)
            return value.isFinite ? Double(value) : nil
        default:
            return nil
        }
    }
}

/// 与内核 `AppleSMC` 驱动对齐的 80 字节结构体。
struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        // 补齐 C 结构体尾部 3 字节对齐填充，防止 Swift 把后续字段塞进来导致偏移错位。
        private var _pad0: UInt8 = 0
        private var _pad1: UInt8 = 0
        private var _pad2: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    private var _padData32: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    var bytesArray: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }
}

// MARK: - IOHID Apple Silicon 温度回退

private enum IOHIDThermalReader {
    private typealias CreateClientFn = @convention(c) (CFAllocator?) -> CFTypeRef?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> CFArray?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> CFTypeRef?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> CFTypeRef?
    private typealias GetFloatValueFn = @convention(c) (CFTypeRef, Int32) -> Double

    private struct Symbols: @unchecked Sendable {
        let createClient: CreateClientFn
        let setMatching: SetMatchingFn
        let copyServices: CopyServicesFn
        let copyProperty: CopyPropertyFn
        let copyEvent: CopyEventFn
        let getFloatValue: GetFloatValueFn
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        else { return nil }
        func load<T>(_ name: String) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        guard
            let createClient: CreateClientFn = load("IOHIDEventSystemClientCreate"),
            let setMatching: SetMatchingFn = load("IOHIDEventSystemClientSetMatching"),
            let copyServices: CopyServicesFn = load("IOHIDEventSystemClientCopyServices"),
            let copyProperty: CopyPropertyFn = load("IOHIDServiceClientCopyProperty"),
            let copyEvent: CopyEventFn = load("IOHIDServiceClientCopyEvent"),
            let getFloatValue: GetFloatValueFn = load("IOHIDEventGetFloatValue")
        else { return nil }
        return Symbols(
            createClient: createClient,
            setMatching: setMatching,
            copyServices: copyServices,
            copyProperty: copyProperty,
            copyEvent: copyEvent,
            getFloatValue: getFloatValue)
    }()

    static func readTemperatures() -> (cpu: Double?, gpu: Double?, ssd: Double?) {
        guard let sym = symbols,
            let client = sym.createClient(kCFAllocatorDefault)
        else { return (nil, nil, nil) }

        // PrimaryUsagePage = 0xFF00 (Apple Vendor), PrimaryUsage = 5 (Temperature)
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 5,
        ]
        sym.setMatching(client, matching as CFDictionary)
        guard let services = sym.copyServices(client) as? [CFTypeRef] else { return (nil, nil, nil) }

        let temperatureEventType: Int64 = 15
        let temperatureField: Int32 = 15 << 16

        var cpuReadings: [Double] = []
        var gpuReadings: [Double] = []
        var ssdReadings: [Double] = []
        var fallbackReadings: [Double] = []

        for service in services {
            guard let event = sym.copyEvent(service, temperatureEventType, 0, 0) else { continue }
            let value = sym.getFloatValue(event, temperatureField)
            guard (10.0...120.0).contains(value) else { continue }

            let name = (sym.copyProperty(service, "Product" as CFString) as? String) ?? ""
            let lower = name.lowercased()
            if lower.contains("gpu") {
                gpuReadings.append(value)
            } else if lower.contains("nand") || lower.contains("ssd") || lower.contains("drive") {
                ssdReadings.append(value)
            } else if lower.contains("tdie") || lower.contains("soc") || lower.contains("cpu")
                || lower.contains("eacc") || lower.contains("pacc")
            {
                cpuReadings.append(value)
            } else {
                fallbackReadings.append(value)
            }
        }

        func average(_ list: [Double]) -> Double? {
            guard !list.isEmpty else { return nil }
            return list.reduce(0, +) / Double(list.count)
        }

        let cpu = average(cpuReadings.isEmpty ? fallbackReadings : cpuReadings)
        let gpu = average(gpuReadings)
        let ssd = average(ssdReadings)
        return (cpu, gpu, ssd)
    }
}
