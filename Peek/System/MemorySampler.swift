import Foundation
import Darwin

/// 内存采集：`host_statistics64` 拿 vm 统计，sysctl 拿内存压力和 swap。
///
/// “已用”的口径对齐活动监视器的“已使用内存”：**App 内存 + 联动内存 + 被压缩内存**。
/// - App 内存 = `internal_page_count − purgeable_count`（匿名页，减去可清除的部分）
/// - 联动内存 = `wire_count`
/// - 被压缩 = `compressor_page_count`
/// 不含文件缓存（`external_page_count`），所以和 active+inactive 的算法相比不会虚高。
struct MemorySampler {
    mutating func sample() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(Self.pageSize)
        let stats = Self.vmStatistics()

        var used: UInt64 = 0
        var appBytes: UInt64 = 0
        var wiredBytes: UInt64 = 0
        var compressedBytes: UInt64 = 0
        var cachedBytes: UInt64 = 0
        if let stats {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeablePages = UInt64(stats.purgeable_count)
            let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
            let wiredPages = UInt64(stats.wire_count)
            let compressedPages = UInt64(stats.compressor_page_count)
            let externalPages = UInt64(stats.external_page_count)

            appBytes = appPages.multipliedReportingOverflow(by: pageSize).partialValue
            wiredBytes = wiredPages.multipliedReportingOverflow(by: pageSize).partialValue
            compressedBytes = compressedPages.multipliedReportingOverflow(by: pageSize).partialValue
            cachedBytes = externalPages.multipliedReportingOverflow(by: pageSize).partialValue

            let pages = appPages + wiredPages + compressedPages
            used = pages.multipliedReportingOverflow(by: pageSize).partialValue
        }
        if total > 0 {
            used = min(used, total)
        }

        let swap = Self.swapUsage()
        return MemoryStats(
            usedBytes: used,
            totalBytes: total,
            pressure: Self.pressure(),
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes)
    }

    private static let pageSize: vm_size_t = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return size
    }()

    private static func vmStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// `kern.memorystatus_vm_pressure_level`：1 正常、2 警告、4 严重。
    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .normal }
        return switch level {
        case 2: .warning
        case 3, 4: .critical
        default: .normal
        }
    }

    /// `vm.swapusage` 给出字节数，读不到就当没有 swap。
    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }
}