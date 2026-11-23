import Darwin
import Foundation

/// 只读一次的系统静态信息：芯片名、物理内存、macOS 版本。
/// 面板头部下方那行小字用它（PEEK-17），不参与秒级采样。
struct SystemInfo: Sendable, Equatable {
    /// 芯片名，如 "M5 Pro"。读不到（或不是 Apple 芯片）时为 nil，面板省略这一段。
    var chipName: String?
    /// 物理内存（字节）。
    var memoryBytes: UInt64
    /// 操作系统版本，如 "27.0"，只取 major.minor。
    var osVersion: String
    /// Apple Silicon 性能核数量（`hw.perflevel0.physicalcpu`），Intel 机型为 nil。
    var performanceCoreCount: Int? = nil
    /// Apple Silicon 能效核数量（`hw.perflevel1.physicalcpu`），Intel 机型为 nil。
    var efficiencyCoreCount: Int? = nil

    /// 进程内只读一次。
    static let current = SystemInfo(
        chipName: chipName(fromBrandString: readBrandString()),
        memoryBytes: ProcessInfo.processInfo.physicalMemory,
        osVersion: osVersionText(ProcessInfo.processInfo.operatingSystemVersion),
        performanceCoreCount: readInt("hw.perflevel0.physicalcpu"),
        efficiencyCoreCount: readInt("hw.perflevel1.physicalcpu"))

    /// 把 `machdep.cpu.brand_string` 整理成芯片名：去掉 "Apple " 前缀和首尾空白。
    /// 空字符串或不认识的前缀照原样保留，全空则返回 nil。
    static func chipName(fromBrandString brand: String?) -> String? {
        guard let brand else { return nil }
        var name = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix(applePrefix) {
            name = String(name.dropFirst(applePrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.isEmpty ? nil : name
    }

    /// "27.0"。不显示补丁号，面板上没必要。
    static func osVersionText(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion)"
    }

    private static let applePrefix = "Apple "

    private static func readBrandString() -> String? {
        let key = "machdep.cpu.brand_string"
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func readInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }
}