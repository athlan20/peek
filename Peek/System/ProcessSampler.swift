import Foundation
import Darwin

/// 进程采集：`proc_listpids` 列出所有进程，`proc_pidinfo(PROC_PIDTASKINFO)` 读 CPU 时间和内存。
///
/// 前后两次采样做差得 CPU 占用（单核满载算 1.0）。读不到的进程（无权限、已退出）直接跳过。
/// 只在独立窗口用，调用频率由 `SamplingEngine` 控制在 5 秒一次。
struct ProcessSampler {
    private var previous: (time: Date, cpuTicks: [Int32: UInt64])?

    /// 预热基线，让紧接着的第一次 `sample()` 就能立刻算出真实 CPU 占用。
    mutating func prime() {
        let now = Date()
        var current: [Int32: UInt64] = [:]
        for pid in Self.allPIDs() where pid > 0 {
            guard let info = Self.taskInfo(pid: pid) else { continue }
            current[pid] = info.pti_total_user &+ info.pti_total_system
        }
        previous = (now, current)
    }

    mutating func sample() -> (topCPU: [ProcessUsage], topMemory: [ProcessUsage]) {
        let now = Date()
        var current: [Int32: UInt64] = [:]
        var usages: [ProcessUsage] = []

        for pid in Self.allPIDs() where pid > 0 {
            guard let info = Self.taskInfo(pid: pid) else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            current[pid] = ticks
            let name = Self.name(pid: pid)
            guard !name.isEmpty else { continue }
            usages.append(
                ProcessUsage(
                    pid: pid, name: name, cpu: 0, memoryBytes: info.pti_resident_size))
        }

        let baseline = previous
        previous = (now, current)

        if let baseline {
            let interval = now.timeIntervalSince(baseline.time)
            // 基线太旧（面板刚重新打开、中间停了很久）就不用它，否则算出来的是长时段均值。
            if interval > 0, interval <= 30 {
                for index in usages.indices {
                    let pid = usages[index].pid
                    guard let before = baseline.cpuTicks[pid],
                        let after = current[pid], after >= before
                    else { continue }
                    usages[index].cpu = Self.seconds(fromTicks: after - before) / interval
                }
            }
        }

        // 分别取按 CPU 排前 5 与按内存排前 5。
        let topCPU = Array(usages.sorted { ($0.cpu, $0.memoryBytes) > ($1.cpu, $1.memoryBytes) }.prefix(5))
        let topMemory = Array(usages.sorted { ($0.memoryBytes, $0.cpu) > ($1.memoryBytes, $1.cpu) }.prefix(5))
        return (topCPU, topMemory)
    }

    /// `proc_taskinfo` 的 CPU 时间是 mach absolute time 计数（不是纳秒），按 timebase 换算成秒。
    private static func seconds(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.numer == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    private static func allPIDs() -> [pid_t] {
        // 先问要多少字节，再按需分配，避免漏掉高 pid 的进程。
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](
            repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 16)
        let used = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard used > 0 else { return [] }
        return Array(pids.prefix(Int(used) / MemoryLayout<pid_t>.stride)).filter { $0 > 0 }
    }

    private static func taskInfo(pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
        return read == Int32(size) ? info : nil
    }

    private static func name(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}