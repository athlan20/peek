import CoreGraphics
import Foundation

/// 按进程归并后的监听端口组，用于「外层按进程分大小、内层端口等大」的分组方块拼图。
struct NetworkProcessGroup: Identifiable, Equatable, Sendable {
    let id: String
    let processName: String
    let ports: [ListeningPort]
    let pids: [Int32]
    let dominantCategory: PortCategory

    /// 给 `TreemapLayout.squarify` 用的面积权重：
    /// 端口数量越多面积越大，同时加一个基础权重避免单端口进程头部过窄。
    var treemapWeight: Double {
        Double(ports.count) + 0.45
    }

    /// 该组内所有端口的活跃 ESTABLISHED 连接总数。
    var totalEstablished: Int {
        ports.reduce(0) { $0 + $1.establishedCount }
    }
}

/// Network 窗口的纯计算逻辑：搜索过滤、按进程分组排序、同 PID 端口查找、组内网格列数计算。
enum NetworkPortGroups {
    /// 按分类和关键词过滤端口（匹配端口号、进程名、PID、监听地址、可执行路径）。
    static func filter(
        _ ports: [ListeningPort],
        query: String,
        category: PortCategory?
    ) -> [ListeningPort] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        return ports.filter { item in
            if let category, item.category != category {
                return false
            }
            guard !trimmed.isEmpty else { return true }
            if String(item.port).contains(trimmed) { return true }
            if item.processName.lowercased().contains(trimmed) { return true }
            if String(item.pid).contains(trimmed) { return true }
            if item.bindAddress.lowercased().contains(trimmed) { return true }
            if let path = item.executablePath?.lowercased(), path.contains(trimmed) { return true }
            return false
        }
    }

    /// 将端口按进程名（忽略大小写）归并成组，并按“端口数降序 → 分类优先级 → 最小端口 → 进程名”排序。
    static func groupByProcess(_ ports: [ListeningPort]) -> [NetworkProcessGroup] {
        guard !ports.isEmpty else { return [] }

        var buckets: [String: (displayName: String, items: [ListeningPort])] = [:]
        for item in ports {
            let key = item.processName.lowercased()
            if var existing = buckets[key] {
                existing.items.append(item)
                buckets[key] = existing
            } else {
                buckets[key] = (item.processName, [item])
            }
        }

        let groups: [NetworkProcessGroup] = buckets.map { key, bucket in
            let sortedPorts = bucket.items.sorted { lhs, rhs in
                if lhs.category.priority != rhs.category.priority {
                    return lhs.category.priority < rhs.category.priority
                }
                if lhs.port != rhs.port {
                    return lhs.port < rhs.port
                }
                return lhs.pid < rhs.pid
            }
            let pids = Array(Set(sortedPorts.map(\.pid))).sorted()
            let dominant = dominantCategory(for: sortedPorts)
            return NetworkProcessGroup(
                id: key,
                processName: bucket.displayName,
                ports: sortedPorts,
                pids: pids,
                dominantCategory: dominant
            )
        }

        return groups.sorted { lhs, rhs in
            if lhs.ports.count != rhs.ports.count {
                return lhs.ports.count > rhs.ports.count
            }
            if lhs.dominantCategory.priority != rhs.dominantCategory.priority {
                return lhs.dominantCategory.priority < rhs.dominantCategory.priority
            }
            let lhsPort = lhs.ports.first?.port ?? 0
            let rhsPort = rhs.ports.first?.port ?? 0
            if lhsPort != rhsPort {
                return lhsPort < rhsPort
            }
            return lhs.processName.localizedCaseInsensitiveCompare(rhs.processName) == .orderedAscending
        }
    }

    /// 找出与指定 PID 共享的所有监听端口（用于终止进程前的二次确认提示）。
    static func portsSharingPID(_ pid: Int32, in ports: [ListeningPort]) -> [ListeningPort] {
        ports
            .filter { $0.pid == pid }
            .sorted { $0.port < $1.port }
    }

    /// 在给定内容区尺寸下，为 `itemCount` 块等大端口瓷砖挑选最均衡的列数。
    /// 目标是让每块瓷砖尽量保持宽略大于高（约 1.35:1）且不小于最小可读宽度。
    static func gridColumns(
        forItemCount itemCount: Int,
        in size: CGSize,
        gap: CGFloat = 6,
        minTileWidth: CGFloat = 86
    ) -> Int {
        guard itemCount > 1, size.width > 0, size.height > 0 else { return 1 }

        let maxByWidth = max(1, Int(floor((size.width + gap) / (minTileWidth + gap))))
        let upperBound = min(itemCount, maxByWidth)
        guard upperBound > 1 else { return 1 }

        let idealAspect: CGFloat = 1.35
        var bestColumns = 1
        var bestScore = CGFloat.greatestFiniteMagnitude

        for cols in 1...upperBound {
            let rows = Int(ceil(Double(itemCount) / Double(cols)))
            let tileW = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let tileH = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            guard tileW > 0, tileH > 0 else { continue }

            let aspect = tileW / tileH
            let aspectPenalty = abs(log(aspect / idealAspect))
            // 轻微惩罚最后一行留白过多
            let emptySlots = CGFloat(cols * rows - itemCount) / CGFloat(cols * rows)
            let score = aspectPenalty + emptySlots * 0.35
            if score < bestScore {
                bestScore = score
                bestColumns = cols
            }
        }
        return bestColumns
    }

    private static func dominantCategory(for ports: [ListeningPort]) -> PortCategory {
        var counts: [PortCategory: Int] = [:]
        for item in ports {
            counts[item.category, default: 0] += 1
        }
        return counts.min { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key.priority < rhs.key.priority
        }?.key ?? .other
    }
}
