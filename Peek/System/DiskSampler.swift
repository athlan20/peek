import Foundation
import IOKit

/// 磁盘采集：容量用 `URLResourceValues`（与“关于本机 → 储存空间”同源），
/// 读写速度用 IOKit `IOBlockStorageDriver` 的 Statistics 累计字节数做差。
struct DiskSampler {
    private var previous: (time: Date, read: UInt64, write: UInt64)?
    /// 磁盘分类估算缓存：60 秒更新一次，避免每秒扫目录。
    private static let breakdownInterval: TimeInterval = 60
    private var cachedBreakdown: (time: Date, apps: UInt64, localCache: UInt64)?

    /// 先记一份基线，第一次采样才有速度。
    mutating func prime() {
        let baseline = Self.cumulativeBytes() ?? (0, 0)
        previous = (Date(), baseline.read, baseline.write)
    }

    mutating func sample() -> DiskStats {
        let now = Date()
        let capacity = Self.capacity()

        let current = Self.cumulativeBytes()
        let baseline = previous
        previous = current.map { (now, $0.read, $0.write) }

        var readRate: Double = 0
        var writeRate: Double = 0
        // 读不到 IOKit 统计（或第一次采样没有基线）就报 0。
        if let current, let baseline {
            let interval = now.timeIntervalSince(baseline.time)
            if interval > 0 {
                let read = current.read &- baseline.read
                let write = current.write &- baseline.write
                // 计数器回绕（换盘、清零）时差值会离谱，直接丢掉这一轮。
                if read < 1 << 50 { readRate = Double(read) / interval }
                if write < 1 << 50 { writeRate = Double(write) / interval }
            }
        }

        let breakdown = estimateBreakdown(now: now, capacity: capacity)

        return DiskStats(
            usedBytes: capacity.used,
            totalBytes: capacity.total,
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate,
            breakdown: breakdown)
    }

    private mutating func estimateBreakdown(
        now: Date, capacity: (used: UInt64, total: UInt64, free: UInt64, purgeable: UInt64)
    ) -> DiskBreakdown {
        if cachedBreakdown == nil
            || now.timeIntervalSince(cachedBreakdown!.time) >= Self.breakdownInterval
        {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let apps =
                Self.boundedDirectorySize(
                    URL(fileURLWithPath: "/Applications"), budgetSeconds: 0.10)
                + Self.boundedDirectorySize(
                    home.appendingPathComponent("Applications"), budgetSeconds: 0.02)
            let localCache = Self.boundedDirectorySize(
                home.appendingPathComponent("Library/Caches"), budgetSeconds: 0.05)
            cachedBreakdown = (now, apps, localCache)
        }

        let used = capacity.used
        guard used > 0 else {
            return DiskBreakdown(
                systemBytes: 0, appsBytes: 0, userBytes: 0, cacheBytes: 0, freeBytes: capacity.free)
        }

        let rawCache = capacity.purgeable + (cachedBreakdown?.localCache ?? 0)
        // 缓存占比上限 40%，避免 APFS purgeable 口径重叠把其余分类挤成 0。
        let cache = min(rawCache, UInt64(Double(used) * 0.40))
        let afterCache = used > cache ? used - cache : 0

        let rawApps = cachedBreakdown?.apps ?? 0
        let apps = min(rawApps, afterCache)
        let rest = afterCache > apps ? afterCache - apps : 0

        // macOS 系统卷 + 系统数据保底约 20 GB，其余归为用户数据。
        let systemFloor: UInt64 = 20_000_000_000
        let systemEstimate = max(systemFloor, UInt64(Double(rest) * 0.28))
        let system = min(rest, systemEstimate)
        let user = rest > system ? rest - system : 0

        return DiskBreakdown(
            systemBytes: system,
            appsBytes: apps,
            userBytes: user,
            cacheBytes: cache,
            freeBytes: capacity.free)
    }

    /// 带时间预算的轻量目录体积统计，超时立刻返回已累计值，确保不卡采样循环。
    private static func boundedDirectorySize(_ url: URL, budgetSeconds: TimeInterval) -> UInt64 {
        let deadline = CFAbsoluteTimeGetCurrent() + budgetSeconds
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
        else { return 0 }

        var total: UInt64 = 0
        var count = 0
        for case let fileURL as URL in enumerator {
            count += 1
            if count & 0xFF == 0, CFAbsoluteTimeGetCurrent() >= deadline {
                break
            }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            if size > 0 {
                total &+= UInt64(size)
            }
        }
        return total
    }

    /// 启动盘的已用 / 总量 / 可用 / 可清除。可用空间用 `volumeAvailableCapacityForImportantUsageKey`，
    /// 和“关于本机 → 储存空间”、Finder 报的数字一致。
    private static func capacity() -> (
        used: UInt64, total: UInt64, free: UInt64, purgeable: UInt64
    ) {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
        let important = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
        let rawFree = UInt64(max(0, values?.volumeAvailableCapacity ?? 0))
        let used = total > important ? total - important : 0
        let purgeable = important > rawFree ? important - rawFree : 0
        return (used, total, important, purgeable)
    }

    /// 所有 `IOBlockStorageDriver` 的累计读写字节数之和（含外接盘，读不到时为 nil）。
    private static func cumulativeBytes() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let property = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0)
            if let stats = property?.takeRetainedValue() as? [String: Any] {
                read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, write)
    }
}