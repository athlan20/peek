import Foundation
import Darwin
import SystemConfiguration

/// 网络采集：`getifaddrs` 的 `if_data` 流量计数做差。
///
/// 只统计默认网卡（`SCDynamicStore` 的 `State:/Network/Global/IPv4` → `PrimaryInterface`）；
/// 查不到默认网卡时退化成所有非回环、状态 up 的网卡之和。
/// `if_data` 的计数是 32 位、会回绕，差值按 `&-` 在 32 位空间里算。
struct NetworkSampler {
    private var previous: (time: Date, interface: String?, down: UInt32, up: UInt32)?
    private var primary: (name: String, time: Date)?

    /// 先记一份基线，第一次采样才有速度。
    mutating func prime() {
        let baseline = Self.counters(primaryInterface: cachedPrimaryInterface())
        previous = (Date(), baseline.interface, baseline.down, baseline.up)
    }

    mutating func sample() -> NetworkStats {
        let now = Date()
        let counters = Self.counters(primaryInterface: cachedPrimaryInterface())
        let baseline = previous
        previous = (now, counters.interface, counters.down, counters.up)

        guard let baseline else { return NetworkStats(downBytesPerSecond: 0, upBytesPerSecond: 0) }
        let interval = now.timeIntervalSince(baseline.time)
        // 两次采样之间换了网卡（计数来源不同）或间隔无效，这一轮报 0。
        guard interval > 0, baseline.interface == counters.interface else {
            return NetworkStats(downBytesPerSecond: 0, upBytesPerSecond: 0)
        }

        let down = UInt64(counters.down &- baseline.down)
        let up = UInt64(counters.up &- baseline.up)
        return NetworkStats(
            downBytesPerSecond: Double(down) / interval, upBytesPerSecond: Double(up) / interval)
    }

    /// 默认网卡 10 秒内复用一次查询结果，避免每秒都建 connect 会话。
    private mutating func cachedPrimaryInterface() -> String? {
        if let primary, Date().timeIntervalSince(primary.time) < 10 { return primary.name }
        let name = Self.primaryInterface()
        primary = name.map { ($0, Date()) }
        return name
    }

    private static func primaryInterface() -> String? {
        guard
            let store = SCDynamicStoreCreate(
                nil, "cc.yuntianyou.peek.network" as CFString, nil, nil),
            let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }

    /// 默认网卡（或所有可用网卡之和）的累计上下行字节数，32 位原始计数。
    /// `interface` 是计数来源：默认网卡名，退化成求和时为 nil。
    private static func counters(primaryInterface: String?)
        -> (interface: String?, down: UInt32, up: UInt32)
    {
        var perInterface: [String: (down: UInt32, up: UInt32)] = [:]
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            return (nil, 0, 0)
        }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            cursor = interface.ifa_next

            // 只有 AF_LINK 的条目带 if_data。
            guard let sockaddr = interface.ifa_addr,
                sockaddr.pointee.sa_family == UInt8(AF_LINK),
                let data = interface.ifa_data,
                interface.ifa_flags & UInt32(IFF_UP) != 0,
                interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0
            else { continue }

            let name = String(cString: interface.ifa_name)
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            perInterface[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }

        if let primaryInterface, let totals = perInterface[primaryInterface] {
            return (primaryInterface, totals.down, totals.up)
        }
        let sum = Self.sum(perInterface)
        return (nil, sum.down, sum.up)
    }

    private static func sum(_ interfaceStats: [String: (down: UInt32, up: UInt32)])
        -> (down: UInt32, up: UInt32)
    {
        interfaceStats.values.reduce(into: (down: UInt32(0), up: UInt32(0))) { total, stats in
            total.down &+= stats.down
            total.up &+= stats.up
        }
    }
}