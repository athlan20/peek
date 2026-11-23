import Foundation
import Darwin

/// CPU 采集：`host_processor_info` 拿每核 tick 数，两次采样做差得占用；`getloadavg` 拿平均负载。
///
/// tick 计数是 32 位、会回绕，所以差值一律按 `&-` 在 32 位空间里算。
struct CPUSampler {
    private struct Ticks {
        /// 每核的忙 tick（user + system + nice）。
        var busy: [UInt32]
        /// 每核的空闲 tick。
        var idle: [UInt32]
    }

    private var previous: Ticks?

    /// 先记一份基线，稍后的第一次采样才有差值可用。
    mutating func prime() {
        previous = Self.readTicks()
    }

    mutating func sample() -> CPUStats {
        let current = Self.readTicks()
        let baseline = previous
        previous = current

        guard let current, let baseline, baseline.busy.count == current.busy.count else {
            return CPUStats(total: 0, perCore: [], load: Self.averageLoad())
        }

        var perCore: [Double] = []
        perCore.reserveCapacity(current.busy.count)
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0

        for index in current.busy.indices {
            let busy = UInt64(current.busy[index] &- baseline.busy[index])
            let idle = UInt64(current.idle[index] &- baseline.idle[index])
            let total = busy + idle
            perCore.append(total == 0 ? 0 : min(1, Double(busy) / Double(total)))
            busySum += busy
            totalSum += total
        }

        let total = totalSum == 0 ? 0 : min(1, Double(busySum) / Double(totalSum))
        return CPUStats(total: total, perCore: perCore, load: Self.averageLoad())
    }

    private static let stateCount = Int(CPU_STATE_MAX)

    private static func readTicks() -> Ticks? {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
        guard result == KERN_SUCCESS, let cpuInfo, numCPUs > 0 else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var busy: [UInt32] = []
        var idle: [UInt32] = []
        busy.reserveCapacity(Int(numCPUs))
        idle.reserveCapacity(Int(numCPUs))

        let idleState = Int(CPU_STATE_IDLE)
        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            var busyTicks: UInt32 = 0
            var idleTicks: UInt32 = 0
            for state in 0..<stateCount {
                // 计数是无符号的 32 位，倒置时 bitPattern 才是原值。
                let ticks = UInt32(bitPattern: cpuInfo[base + state])
                if state == idleState {
                    idleTicks = ticks
                } else {
                    busyTicks &+= ticks
                }
            }
            busy.append(busyTicks)
            idle.append(idleTicks)
        }
        return Ticks(busy: busy, idle: idle)
    }

    private static func averageLoad() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count > 0 else { return [] }
        return Array(loads.prefix(Int(count)))
    }
}