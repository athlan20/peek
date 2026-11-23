import Darwin
import Foundation
import IOKit

/// 温度与风扇转速采集：优先通过 IOKit 的 `AppleSMC` 读取 CPU / GPU / SSD 温度和风扇转速，
/// Apple Silicon 上若某类 SMC 温度键读不到，再回退到 IOHID 温度传感器。
/// 无风扇机型（如 MacBook Air）或读不到时返回 nil，由面板优雅降级展示。
struct ThermalSampler {
    /// 记住本机 IOHID 实际存在哪些通道，避免 SMC 缺失某通道（如无 SSD 传感器）时每秒徒劳全扫 IOHID。
    private var hidAvailability: (cpu: Bool, gpu: Bool, ssd: Bool)?

    mutating func sample() -> ThermalStats {
        var cpuTemp: Double?
        var gpuTemp: Double?
        var ssdTemp: Double?
        var fanRPM: Int?
        var fanCount = 0

        if let smc = SMCConnection.shared {
            let fans = smc.readFans()
            fanCount = fans.count
            fanRPM = fans.rpm
            cpuTemp = smc.readCPUTemperature()
            gpuTemp = smc.readGPUTemperature()
            ssdTemp = smc.readSSDTemperature()
        }

        let needCPU = cpuTemp == nil && (hidAvailability?.cpu ?? true)
        let needGPU = gpuTemp == nil && (hidAvailability?.gpu ?? true)
        let needSSD = ssdTemp == nil && (hidAvailability?.ssd ?? true)

        if needCPU || needGPU || needSSD {
            let hid = IOHIDThermalReader.readTemperatures(
                needCPU: needCPU, needGPU: needGPU, needSSD: needSSD)
            if hidAvailability == nil {
                hidAvailability = (hid.cpu != nil, hid.gpu != nil, hid.ssd != nil)
            }
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

// MARK: - AppleSMC（纯只读，持久连接 + 键元数据与有效键缓存）

private final class SMCConnection: @unchecked Sendable {
    static let shared = SMCConnection()

    private let connection: io_connect_t
    private let lock = NSLock()
    /// 缓存每个 4CC 键的 `(dataSize, dataType)`（若该键在本机不存在则存 `nil`），避免每秒重复发 selector 9。
    private var keyInfoCache: [UInt32: (size: UInt32, type: UInt32)?] = [:]
    /// 首次探测后记住本机实际有效的温度键列表，后续只读有效键。
    private var activeCPUKeys: [String]?
    private var activeGPUKeys: [String]?
    private var activeSSDKeys: [String]?
    private var cachedFanCount: Int?

    private static let candidateCPUKeys = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j",
        "Tc0a", "Tc0b", "TC0P", "TC0D", "TC0E", "TC0F", "TC0C", "TC1C",
    ]

    private static let candidateGPUKeys = [
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        "Tg04", "Tg0C", "Tg0K", "Tg0S", "Tg1b", "Tg1p", "Tg0P",
        "TG0D", "TG0P", "TG0E", "TG0F",
    ]

    private static let candidateSSDKeys = [
        "TH0a", "TH0b", "TH0c", "TH0x", "TH1a", "TH1b",
        "TN0D", "TN0P", "TN0H",
    ]

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

    deinit {
        IOServiceClose(connection)
    }

    func readFans() -> (count: Int, rpm: Int?) {
        lock.lock()
        defer { lock.unlock() }

        let count: Int
        if let cached = cachedFanCount {
            count = cached
        } else if let countValue = readDoubleLocked(key: "FNum") {
            count = max(0, min(8, Int(countValue.rounded())))
            cachedFanCount = count
        } else {
            cachedFanCount = 0
            return (0, nil)
        }
        guard count > 0 else { return (0, nil) }

        var maxRPM: Double?
        for index in 0..<count {
            if let rpm = readDoubleLocked(key: "F\(index)Ac"), rpm >= 0, rpm < 20_000 {
                maxRPM = max(maxRPM ?? 0, rpm)
            }
        }
        return (count, maxRPM.map { Int($0.rounded()) })
    }

    func readCPUTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return readAverageTemperatureLocked(
            candidates: Self.candidateCPUKeys, activeCache: &activeCPUKeys)
    }

    func readGPUTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return readAverageTemperatureLocked(
            candidates: Self.candidateGPUKeys, activeCache: &activeGPUKeys)
    }

    func readSSDTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return readAverageTemperatureLocked(
            candidates: Self.candidateSSDKeys, activeCache: &activeSSDKeys)
    }

    private func readAverageTemperatureLocked(
        candidates: [String], activeCache: inout [String]?
    ) -> Double? {
        let keysToRead = activeCache ?? candidates
        var readings: [Double] = []
        var discovered: [String] = []

        for key in keysToRead {
            if let value = readDoubleLocked(key: key), (10.0...120.0).contains(value) {
                readings.append(value)
                if activeCache == nil {
                    discovered.append(key)
                }
            }
        }
        if activeCache == nil {
            activeCache = discovered
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    private func readDoubleLocked(key: String) -> Double? {
        guard let fourCC = Self.fourCharCode(key) else { return nil }

        let keyMeta: (size: UInt32, type: UInt32)
        if let cached = keyInfoCache[fourCC] {
            guard let valid = cached else { return nil }
            keyMeta = valid
        } else {
            // 第一步：查询键的 dataSize 和 dataType（selector 9 = kSMCGetKeyInfo），结果永久缓存。
            var infoInput = SMCKeyData()
            infoInput.key = fourCC
            infoInput.data8 = 9
            guard let infoOutput = call(input: infoInput) else {
                keyInfoCache[fourCC] = nil
                return nil
            }
            let dataSize = infoOutput.keyInfo.dataSize
            let dataType = infoOutput.keyInfo.dataType
            guard dataSize > 0, dataSize <= 32 else {
                keyInfoCache[fourCC] = nil
                return nil
            }
            keyMeta = (dataSize, dataType)
            keyInfoCache[fourCC] = keyMeta
        }

        // 第二步：读取键的原始字节（selector 5 = kSMCReadKey）。
        var readInput = SMCKeyData()
        readInput.key = fourCC
        readInput.keyInfo.dataSize = keyMeta.size
        readInput.data8 = 5
        guard let readOutput = call(input: readInput) else { return nil }

        let bytes = readOutput.bytesArray
        return Self.decode(bytes: bytes, size: Int(keyMeta.size), type: keyMeta.type)
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

    private enum SensorKind {
        case cpu, gpu, ssd, other
    }

    private struct CachedClient: @unchecked Sendable {
        let sensors: [(service: CFTypeRef, kind: SensorKind)]
    }

    private static let cachedClient: CachedClient? = {
        guard let sym = symbols,
            let client = sym.createClient(kCFAllocatorDefault)
        else { return nil }

        // PrimaryUsagePage = 0xFF00 (Apple Vendor), PrimaryUsage = 5 (Temperature)
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 5,
        ]
        sym.setMatching(client, matching as CFDictionary)
        guard let services = sym.copyServices(client) as? [CFTypeRef] else { return nil }

        var list: [(CFTypeRef, SensorKind)] = []
        list.reserveCapacity(services.count)
        for service in services {
            let name = (sym.copyProperty(service, "Product" as CFString) as? String) ?? ""
            let lower = name.lowercased()
            let kind: SensorKind
            if lower.contains("gpu") {
                kind = .gpu
            } else if lower.contains("nand") || lower.contains("ssd") || lower.contains("drive") {
                kind = .ssd
            } else if lower.contains("tdie") || lower.contains("soc") || lower.contains("cpu")
                || lower.contains("eacc") || lower.contains("pacc")
            {
                kind = .cpu
            } else {
                kind = .other
            }
            list.append((service, kind))
        }
        return CachedClient(sensors: list)
    }()

    static func readTemperatures(
        needCPU: Bool = true, needGPU: Bool = true, needSSD: Bool = true
    ) -> (cpu: Double?, gpu: Double?, ssd: Double?) {
        guard let sym = symbols, let cached = cachedClient else { return (nil, nil, nil) }

        let temperatureEventType: Int64 = 15
        let temperatureField: Int32 = 15 << 16

        var cpuReadings: [Double] = []
        var gpuReadings: [Double] = []
        var ssdReadings: [Double] = []
        var fallbackReadings: [Double] = []

        for item in cached.sensors {
            switch item.kind {
            case .cpu, .other:
                guard needCPU else { continue }
            case .gpu:
                guard needGPU else { continue }
            case .ssd:
                guard needSSD else { continue }
            }
            guard let event = sym.copyEvent(item.service, temperatureEventType, 0, 0) else { continue }
            let value = sym.getFloatValue(event, temperatureField)
            guard (10.0...120.0).contains(value) else { continue }

            switch item.kind {
            case .gpu: gpuReadings.append(value)
            case .ssd: ssdReadings.append(value)
            case .cpu: cpuReadings.append(value)
            case .other: fallbackReadings.append(value)
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
