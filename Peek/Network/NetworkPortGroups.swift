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

/// 整齐 Bento 栅格中的单个进程槽位：按端口数量跨 1...totalColumns 列，保证所有端口瓷砖等宽等高、列线严格对齐。
struct NetworkBentoSlot: Identifiable, Equatable, Sendable {
    let group: NetworkProcessGroup
    let span: Int
    let innerColumns: Int

    var id: String { group.id }

    /// 该槽位内部端口瓷砖的行数。
    var innerRows: Int {
        max(1, Int(ceil(Double(group.ports.count) / Double(max(1, innerColumns)))))
    }
}

/// 整齐 Bento 栅格中的一行，行内所有槽位顶底对齐。
struct NetworkBentoRow: Identifiable, Equatable, Sendable {
    let id: String
    let slots: [NetworkBentoSlot]

    /// 本行内所有槽位中最大的内部瓷砖行数，用于统一本行高度。
    var maxInnerRows: Int {
        slots.map(\.innerRows).max() ?? 1
    }
}

/// Network 窗口的纯计算逻辑：搜索过滤、按进程分组排序、同 PID 端口查找、整齐 Bento 跨列行打包。
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

    /// 根据画布宽度计算等大端口瓷砖矩阵的列数（默认 4 列，宽屏最多 6 列，窄屏最少 3 列）。
    static func tileColumns(
        forWidth width: CGFloat,
        gap: CGFloat = 10,
        minTileWidth: CGFloat = 144
    ) -> Int {
        guard width > 0 else { return 4 }
        let raw = Int(floor((width + gap) / (minTileWidth + gap)))
        return max(3, min(6, raw))
    }

    /// 根据画布宽度计算整齐 Bento 栅格的总列数（通常 3~4 列，确保单列进程名与端口完整可读）。
    static func totalColumns(
        forWidth width: CGFloat,
        gap: CGFloat = 10,
        minColumnWidth: CGFloat = 185
    ) -> Int {
        guard width > 0 else { return 3 }
        let raw = Int(floor((width + gap) / (minColumnWidth + gap)))
        return max(2, min(5, raw))
    }

    /// 计算单个进程组在 `totalColumns` 栅格中的跨列数与内部列数：
    /// - 1 个端口 → 1×1
    /// - 2 个端口 → 2×1（并排 2 块等大瓷砖）
    /// - 3 个端口 → 3×1（宽屏下并排 3 块）
    /// - 4 个端口 → 2×2（紧凑方阵）
    /// - 5+ 个端口 → 占满整行
    static func slotSpec(forPortCount count: Int, totalColumns: Int) -> (span: Int, innerColumns: Int) {
        let cols = max(1, totalColumns)
        switch count {
        case ...1:
            return (1, 1)
        case 2:
            let span = min(2, cols)
            return (span, span)
        case 3:
            let span = min(3, cols)
            return (span, span)
        case 4:
            let span = min(2, cols)
            return (span, span)
        default:
            return (cols, cols)
        }
    }

    /// 采用 First-Fit 行打包将进程组排入整齐 Bento 栅格，杜绝细长残片并保证每行左右边缘对齐。
    static func bentoRows(
        for groups: [NetworkProcessGroup],
        totalColumns: Int
    ) -> [NetworkBentoRow] {
        let cols = max(1, totalColumns)
        var remaining = groups
        var rows: [NetworkBentoRow] = []

        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            let firstSpec = slotSpec(forPortCount: first.ports.count, totalColumns: cols)
            var rowSlots = [
                NetworkBentoSlot(group: first, span: firstSpec.span, innerColumns: firstSpec.innerColumns)
            ]
            var used = firstSpec.span

            var idx = 0
            while used < cols && idx < remaining.count {
                let candidate = remaining[idx]
                let spec = slotSpec(forPortCount: candidate.ports.count, totalColumns: cols)
                if used + spec.span <= cols {
                    rowSlots.append(
                        NetworkBentoSlot(group: candidate, span: spec.span, innerColumns: spec.innerColumns)
                    )
                    used += spec.span
                    remaining.remove(at: idx)
                } else {
                    idx += 1
                }
            }

            let rowID = rowSlots.map(\.id).joined(separator: "|")
            rows.append(NetworkBentoRow(id: rowID, slots: rowSlots))
        }

        return rows
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
