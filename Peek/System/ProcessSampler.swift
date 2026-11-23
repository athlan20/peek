import Foundation
import Darwin

/// 进程采集：`proc_listpids` 列出所有进程，`proc_pidinfo(PROC_PIDTASKINFO)` 读 CPU 时间和内存。
///
/// 前后两次采样做差得 CPU 占用（单核满载算 1.0）。读不到的进程（无权限、已退出）直接跳过。
/// 只为排进前 5 的候选进程调用 `proc_name`，并缓存进程名，避免对数百个进程重复发起系统调用。
struct ProcessSampler {
    private var previous: (time: Date, cpuTicks: [Int32: UInt64])?
    private var nameCache: [Int32: String] = [:]

    /// 预热基线，让紧接着的第一次 `sample()` 就能立刻算出真实 CPU 占用。
    mutating func prime() {
        let now = Date()
        var current = [Int32: UInt64](minimumCapacity: 512)
        for pid in Self.allPIDs() where pid > 0 {
            guard let info = Self.taskInfo(pid: pid) else { continue }
            current[pid] = info.pti_total_user &+ info.pti_total_system
        }
        previous = (now, current)
    }

    mutating func sample() -> (topCPU: [ProcessUsage], topMemory: [ProcessUsage]) {
        let now = Date()
        let pids = Self.allPIDs()
        var current = [Int32: UInt64](minimumCapacity: pids.count)

        struct RawSample {
            var pid: Int32
            var cpu: Double
            var memoryBytes: UInt64
        }

        // 只维护前 10 个候选（预留余量防个别进程名不可读），避免对 700+ 进程做两次全量排序。
        let candidateLimit = 10
        var byCPU: [RawSample] = []
        var byMemory: [RawSample] = []
        byCPU.reserveCapacity(candidateLimit + 1)
        byMemory.reserveCapacity(candidateLimit + 1)

        func insertTop(
            _ sample: RawSample,
            into list: inout [RawSample],
            higher: (RawSample, RawSample) -> Bool
        ) {
            if list.count == candidateLimit, let last = list.last, !higher(sample, last) {
                return
            }
            var idx = list.count
            while idx > 0 && higher(sample, list[idx - 1]) {
                idx -= 1
            }
            list.insert(sample, at: idx)
            if list.count > candidateLimit {
                list.removeLast()
            }
        }

        let baseline = previous
        let validInterval: TimeInterval? = {
            guard let baseline else { return nil }
            let dt = now.timeIntervalSince(baseline.time)
            return (dt > 0 && dt <= 30) ? dt : nil
        }()

        for pid in pids where pid > 0 {
            guard let info = Self.taskInfo(pid: pid) else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            current[pid] = ticks

            var cpu = 0.0
            if let dt = validInterval,
                let before = baseline?.cpuTicks[pid],
                ticks >= before
            {
                cpu = Self.seconds(fromTicks: ticks - before) / dt
            }
            let sample = RawSample(pid: pid, cpu: cpu, memoryBytes: info.pti_resident_size)
            insertTop(sample, into: &byCPU) { ($0.cpu, $0.memoryBytes) > ($1.cpu, $1.memoryBytes) }
            insertTop(sample, into: &byMemory) { ($0.memoryBytes, $0.cpu) > ($1.memoryBytes, $1.cpu) }
        }

        previous = (now, current)

        // 清理已退出进程的缓存，防止长期运行字典无限增长。
        if nameCache.count > current.count + 128 {
            nameCache = nameCache.filter { current[$0.key] != nil }
        }

        // 只对排在前面的候选查进程名（通常只需查 5~10 个 PID）。

        var topCPU: [ProcessUsage] = []
        topCPU.reserveCapacity(5)
        for item in byCPU {
            guard topCPU.count < 5 else { break }
            let procName = resolvedName(pid: item.pid)
            guard !procName.isEmpty else { continue }
            topCPU.append(
                ProcessUsage(pid: item.pid, name: procName, cpu: item.cpu, memoryBytes: item.memoryBytes))
        }

        var topMemory: [ProcessUsage] = []
        topMemory.reserveCapacity(5)
        for item in byMemory {
            guard topMemory.count < 5 else { break }
            let procName = resolvedName(pid: item.pid)
            guard !procName.isEmpty else { continue }
            topMemory.append(
                ProcessUsage(pid: item.pid, name: procName, cpu: item.cpu, memoryBytes: item.memoryBytes))
        }

        return (topCPU, topMemory)
    }

    private mutating func resolvedName(pid: Int32) -> String {
        if let cached = nameCache[pid] {
            return cached
        }
        let fetched = Self.name(pid: pid)
        if !fetched.isEmpty {
            nameCache[pid] = fetched
        }
        return fetched
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