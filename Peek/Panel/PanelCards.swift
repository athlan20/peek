import SwiftUI

// MARK: - 1. CPU Card

struct CPUCard: View {
    let stats: CPUStats
    let topProcesses: [ProcessUsage]

    @State private var isHovered = false
    @State private var hoveredSlot: Int?

    private var coreCount: Int { max(1, stats.perCore.count) }
    private var isAlert: Bool { stats.total >= MetricThreshold.cpu }
    private var top5: [ProcessUsage] { PanelFormat.topProcesses(topProcesses, limit: 5) }

    private var hoveredProcess: ProcessUsage? {
        guard let slot = hoveredSlot, slot >= 0, slot < top5.count else { return nil }
        return top5[slot]
    }

    var body: some View {
        BentoCard(
            borderColor: PanelPalette.cpuAccent,
            topGlow: PanelPalette.cpuGlow,
            isAlert: isAlert,
            isHovered: isHovered
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 5) {
                    Text("CPU")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PanelPalette.textPrimary)
                    if isAlert { AlertPulseDot() }
                    Spacer()
                    Text(verbatim: PanelFormat.percent(stats.total))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isAlert ? PanelPalette.alertAccent : PanelPalette.textPrimary)
                }

                ThinMetricBar(
                    fraction: stats.total,
                    tint: isAlert ? PanelPalette.alertAccent : PanelPalette.cpuAccent
                )

                ProcessMondrianGrid(
                    processes: top5,
                    mode: .cpu,
                    hoveredSlot: $hoveredSlot
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 2)

                // 悬停在某个进程方块上时，底部栏实时切换为该进程的详细信息；移开后恢复核心数与 Load 柱。
                Group {
                    if let proc = hoveredProcess {
                        hoveredProcessFooter(proc)
                    } else {
                        HStack(spacing: 4) {
                            Text(verbatim: coreSummaryText)
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(PanelPalette.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            loadAverageMicroMeter
                        }
                    }
                }
                .frame(height: 13)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredSlot = nil }
        }
        .animation(.easeOut(duration: 0.14), value: hoveredSlot)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("CPU \(PanelFormat.percent(stats.total))"))
    }

    private func hoveredProcessFooter(_ proc: ProcessUsage) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(PanelPalette.cpuAccent)
                .frame(width: 4.5, height: 4.5)
            Text(verbatim: proc.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 3)
            Text(verbatim: PanelFormat.cpuPercent(proc.cpu))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(PanelPalette.cpuAccent)
            Text(verbatim: "·")
                .font(.system(size: 8.5))
                .foregroundStyle(PanelPalette.textMuted)
            Text(verbatim: PanelFormat.bytes(proc.memoryBytes))
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
        }
        .lineLimit(1)
    }

    /// 底部核心标签：Apple Silicon 有 P/E 核且总数匹配时显示如 "10C · 4P 6E"，否则显示 "Core 1-N"。
    private var coreSummaryText: String {
        let info = SystemInfo.current
        if let p = info.performanceCoreCount, let e = info.efficiencyCoreCount, p + e == coreCount {
            return "\(coreCount)C · \(p)P \(e)E"
        }
        return "Core 1-\(coreCount)"
    }

    /// 右下角 3 组像素柱：分别对应 1m / 5m / 15m 系统平均负载（相对核心数归一化）。
    private var loadAverageMicroMeter: some View {
        let loads = Array(stats.load.prefix(3))
        let normalized: [Double] = (0..<3).map { index in
            let raw = index < loads.count ? loads[index] : 0
            return raw / Double(max(1, coreCount))
        }

        return HStack(spacing: 3.5) {
            ForEach(0..<3, id: \.self) { index in
                loadMiniColumn(ratio: normalized[index])
            }
        }
        .help(
            Text(
                "Load 1m / 5m / 15m: \(stats.load.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: " / "))"
            )
        )
    }

    private func loadMiniColumn(ratio: Double) -> some View {
        let litRows: Int = if ratio >= 0.66 {
            3
        } else if ratio >= 0.33 {
            2
        } else if ratio > 0.03 {
            1
        } else {
            0
        }
        let tint: Color = if ratio >= 1.0 {
            PanelPalette.alertAccent
        } else if ratio >= 0.66 {
            PanelPalette.segYellow
        } else if ratio >= 0.33 {
            PanelPalette.cpuAccent
        } else {
            PanelPalette.segTeal
        }

        return VStack(spacing: 1.4) {
            ForEach((0..<3).reversed(), id: \.self) { rowFromBottom in
                let isLit = rowFromBottom < litRows
                HStack(spacing: 1.4) {
                    RoundedRectangle(cornerRadius: 0.6)
                        .fill(isLit ? tint : PanelPalette.inactivePixel)
                        .frame(width: 2.5, height: 2.5)
                    RoundedRectangle(cornerRadius: 0.6)
                        .fill(isLit ? tint : PanelPalette.inactivePixel)
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
    }
}

/// 进程 Mondrian 块展示模式：CPU（冷色翡翠/青蓝，按 CPU 占比排布）与 MEM（暖色珊瑚/橙/琥珀，按内存占比排布）。
private enum ProcessMondrianMode: Equatable {
    case cpu
    case memory(totalBytes: UInt64)

    var hoverGlowColor: Color {
        switch self {
        case .cpu: PanelPalette.cpuAccent
        case .memory: PanelPalette.memAccent
        }
    }

    func valueLabel(for process: ProcessUsage) -> String {
        switch self {
        case .cpu:
            return PanelFormat.cpuPercent(process.cpu)
        case .memory:
            return Self.compactBytes(process.memoryBytes)
        }
    }

    func fillColor(for process: ProcessUsage?, rank: Int) -> Color {
        guard let process else {
            return PanelPalette.inactivePixel.opacity(0.60)
        }
        switch self {
        case .cpu:
            if process.cpu >= 1.20 {
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.62, green: 0.22, blue: 0.22, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFECACA)
                )
            }
            if process.cpu >= 0.70 {
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.58, green: 0.44, blue: 0.14, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFDE68A)
                )
            }
            switch rank {
            case 0:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.12, green: 0.48, blue: 0.36, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xC2F5DF)
                )
            case 1:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.11, green: 0.40, blue: 0.43, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xBCEFE6)
                )
            case 2:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.13, green: 0.33, blue: 0.41, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xCEE9FC)
                )
            case 3:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.13, green: 0.27, blue: 0.36, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xDCE7F5)
                )
            default:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.14, green: 0.22, blue: 0.31, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xE6ECF4)
                )
            }
        case .memory(let totalBytes):
            let share = totalBytes > 0 ? Double(process.memoryBytes) / Double(totalBytes) : 0
            if share >= 0.25 {
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.68, green: 0.20, blue: 0.22, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFECACA)
                )
            }
            switch rank {
            case 0:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.56, green: 0.21, blue: 0.24, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFFD5DA)
                )
            case 1:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.54, green: 0.28, blue: 0.20, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFDE0C2)
                )
            case 2:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.49, green: 0.33, blue: 0.19, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFDE9B2)
                )
            case 3:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.40, green: 0.24, blue: 0.24, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xFBD6E6)
                )
            default:
                return PanelPalette.dynamic(
                    dark: NSColor(srgbRed: 0.30, green: 0.20, blue: 0.25, alpha: 1),
                    light: PanelPalette.nsColor(hex: 0xECE4F2)
                )
            }
        }
    }

    var tilePrimaryText: Color {
        switch self {
        case .cpu:
            PanelPalette.dynamic(
                dark: NSColor.white.withAlphaComponent(0.95),
                light: PanelPalette.nsColor(hex: 0x064E3B)
            )
        case .memory:
            PanelPalette.dynamic(
                dark: NSColor.white.withAlphaComponent(0.95),
                light: PanelPalette.nsColor(hex: 0x7F1D1D)
            )
        }
    }

    var tileSecondaryText: Color {
        switch self {
        case .cpu:
            PanelPalette.dynamic(
                dark: NSColor.white.withAlphaComponent(0.78),
                light: PanelPalette.nsColor(hex: 0x064E3B, alpha: 0.72)
            )
        case .memory:
            PanelPalette.dynamic(
                dark: NSColor.white.withAlphaComponent(0.78),
                light: PanelPalette.nsColor(hex: 0x7F1D1D, alpha: 0.72)
            )
        }
    }

    func borderTint(for process: ProcessUsage?, rank: Int, isHovered: Bool) -> Color {
        if isHovered { return PanelPalette.treemapSelectionBorder }
        guard let process else { return PanelPalette.inactivePixel }
        switch self {
        case .cpu:
            if process.cpu >= 1.20 { return PanelPalette.alertAccent }
            if process.cpu >= 0.70 { return PanelPalette.segYellow }
            return rank == 0 ? PanelPalette.cpuAccent : PanelPalette.segTeal
        case .memory(let totalBytes):
            let share = totalBytes > 0 ? Double(process.memoryBytes) / Double(totalBytes) : 0
            if share >= 0.25 { return PanelPalette.alertAccent }
            return rank == 0 ? PanelPalette.memAccent : PanelPalette.segOrange
        }
    }

    /// 紧凑内存数字，如 "3.2G"、"980M"，在紧凑小块里也能完整展示。
    private static func compactBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1fG", gb)
        }
        let mb = Int((Double(bytes) / 1_048_576).rounded())
        return "\(max(1, mb))M"
    }
}

/// CPU / MEM 卡片共用的常驻 5 块非对称 Mondrian Bento 布局（槽位 0..<5 永不淡出消失），
/// 用嵌套 `HStack` / `VStack` 严格锁死 3pt 间距，在阻尼弹簧形变全程绝不重叠、绝不错位。
private struct ProcessMondrianGrid: View {
    let processes: [ProcessUsage]
    let mode: ProcessMondrianMode
    @Binding var hoveredSlot: Int?

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let weights = Self.fiveWeights(for: processes, mode: mode)
            let dims = Self.mondrianDimensions(weights: weights, in: proxy.size, gap: gap)

            HStack(spacing: gap) {
                // Slot 0 (#1 Hero)
                slotTile(0, width: dims.leftW, height: proxy.size.height)

                VStack(spacing: gap) {
                    // Slot 1 (#2 Top-Right)
                    slotTile(1, width: dims.rightW, height: dims.topH)

                    HStack(spacing: gap) {
                        // Slot 2 (#3 Bottom-Middle)
                        slotTile(2, width: dims.c2W, height: dims.botH)

                        VStack(spacing: gap) {
                            // Slot 3 (#4)
                            slotTile(3, width: dims.stackW, height: dims.c3H)
                            // Slot 4 (#5)
                            slotTile(4, width: dims.stackW, height: dims.c4H)
                        }
                        .frame(width: dims.stackW, height: dims.botH)
                    }
                    .frame(width: dims.rightW, height: dims.botH)
                }
                .frame(width: dims.rightW, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .animation(
                .easeOut(duration: 0.18),
                value: dims
            )
        }
    }

    private func slotTile(_ slot: Int, width: CGFloat, height: CGFloat) -> some View {
        let proc = slot < processes.count ? processes[slot] : nil
        let isTileHovered = hoveredSlot == slot && proc != nil
        return ProcessMondrianTile(
            process: proc,
            mode: mode,
            rank: slot,
            width: width,
            height: height,
            isHovered: isTileHovered
        )
        .frame(width: width, height: height)
        .onHover { hovering in
            if hovering, proc != nil {
                hoveredSlot = slot
            } else if hoveredSlot == slot {
                hoveredSlot = nil
            }
        }
    }

    private struct MondrianDimensions: Equatable {
        var leftW: CGFloat = 0
        var rightW: CGFloat = 0
        var topH: CGFloat = 0
        var botH: CGFloat = 0
        var c2W: CGFloat = 0
        var stackW: CGFloat = 0
        var c3H: CGFloat = 0
        var c4H: CGFloat = 0
    }

    private static func fiveWeights(for processes: [ProcessUsage], mode: ProcessMondrianMode) -> [Double] {
        guard !processes.isEmpty else {
            return [38, 26, 16, 12, 8]
        }
        switch mode {
        case .cpu:
            let hasCPU = processes.contains { $0.cpu > 0.005 }
            return (0..<5).map { idx in
                guard idx < processes.count else { return 0.01 }
                let proc = processes[idx]
                return hasCPU ? max(proc.cpu, 0.015) : max(Double(proc.memoryBytes), 1)
            }
        case .memory:
            return (0..<5).map { idx in
                guard idx < processes.count else { return 1 }
                return max(Double(processes[idx].memoryBytes), 1)
            }
        }
    }

    private static func mondrianDimensions(
        weights: [Double], in size: CGSize, gap: CGFloat
    ) -> MondrianDimensions {
        guard weights.count == 5, size.width > gap * 2, size.height > gap * 2 else {
            return MondrianDimensions()
        }
        let w0 = weights[0], w1 = weights[1], w2 = weights[2], w3 = weights[3], w4 = weights[4]
        let total = max(0.001, w0 + w1 + w2 + w3 + w4)
        let restSum = max(0.001, w1 + w2 + w3 + w4)

        let usableW = size.width - gap
        let usableH = size.height - gap

        // 量化到 2pt 步长，避免进程 CPU 1%~2% 的微小波动每 2 秒触发整组 Mondrian 块动画重排。
        func snap(_ value: CGFloat) -> CGFloat {
            (value / 2).rounded() * 2
        }

        let heroShare = min(0.56, max(0.32, (w0 / total) * 1.15))
        let leftW = snap(usableW * heroShare)
        let rightW = max(0, usableW - leftW)

        let topShare = min(0.56, max(0.36, (w1 / restSum) * 1.10))
        let topH = snap(usableH * topShare)
        let botH = max(0, usableH - topH)

        let botUsableW = max(0, rightW - gap)
        let botSum = max(0.001, w2 + w3 + w4)
        let c2Share = min(0.62, max(0.38, (w2 / botSum) * 1.05))
        let c2W = snap(botUsableW * c2Share)
        let stackW = max(0, botUsableW - c2W)

        let stackUsableH = max(0, botH - gap)
        let pairSum = max(0.001, w3 + w4)
        let c3Share = min(0.62, max(0.38, w3 / pairSum))
        let c3H = snap(stackUsableH * c3Share)
        let c4H = max(0, stackUsableH - c3H)

        return MondrianDimensions(
            leftW: leftW, rightW: rightW,
            topH: topH, botH: botH,
            c2W: c2W, stackW: stackW,
            c3H: c3H, c4H: c4H
        )
    }
}

private struct ProcessMondrianTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let process: ProcessUsage?
    let mode: ProcessMondrianMode
    let rank: Int
    let width: CGFloat
    let height: CGFloat
    let isHovered: Bool

    var body: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let fillColor = mode.fillColor(for: process, rank: rank)
        let borderTint = mode.borderTint(for: process, rank: rank, isHovered: isHovered)

        shape
            .fill(fillColor)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: isLight
                            ? [
                                Color.white.opacity(isHovered ? 0.55 : 0.36),
                                Color.clear,
                            ]
                            : [
                                Color.white.opacity(isHovered ? 0.22 : 0.11),
                                Color.clear,
                                Color.black.opacity(0.18),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .topLeading) {
                if let process {
                    tileLabels(process)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                }
            }
            .overlay {
                shape.strokeBorder(
                    borderTint.opacity(isHovered ? 0.85 : (isLight ? 0.26 : (rank == 0 ? 0.52 : 0.28))),
                    lineWidth: isHovered ? 1.2 : 0.75
                )
            }
            .clipShape(shape)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .help(tooltipText)
    }

    private var tooltipText: Text {
        guard let process else { return Text("") }
        return Text(
            "\(process.name) (PID \(String(process.pid)))\nMemory: \(PanelFormat.bytes(process.memoryBytes))\nCPU: \(PanelFormat.cpuPercent(process.cpu))"
        )
    }

    @ViewBuilder
    private func tileLabels(_ process: ProcessUsage) -> some View {
        let value = mode.valueLabel(for: process)
        if width >= 34 && height >= 28 {
            VStack(alignment: .leading, spacing: 0.5) {
                Text(verbatim: process.name)
                    .font(.system(size: width >= 66 ? 9.5 : 8.2, weight: .semibold))
                    .foregroundStyle(mode.tilePrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: value)
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundStyle(mode.tileSecondaryText)
                    .lineLimit(1)
            }
        } else if width >= 54 && height >= 16 {
            HStack(spacing: 3) {
                Text(verbatim: process.name)
                    .font(.system(size: 8.2, weight: .semibold))
                    .foregroundStyle(mode.tilePrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text(verbatim: value)
                    .font(.system(size: 7.8, weight: .medium).monospacedDigit())
                    .foregroundStyle(mode.tileSecondaryText)
                    .lineLimit(1)
            }
        } else if width >= 22 && height >= 13 {
            Text(verbatim: value)
                .font(.system(size: 7.5, weight: .medium).monospacedDigit())
                .foregroundStyle(mode.tilePrimaryText.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - 2. MEM Card

struct MemoryCard: View {
    let stats: MemoryStats
    let topMemoryProcesses: [ProcessUsage]

    @State private var isHovered = false
    @State private var hoveredSlot: Int?

    private var isAlert: Bool {
        stats.usedFraction >= MetricThreshold.memory || stats.pressure != .normal
    }

    private var top5: [ProcessUsage] {
        PanelFormat.topMemoryProcesses(topMemoryProcesses, limit: 5)
    }

    private var hoveredProcess: ProcessUsage? {
        guard let slot = hoveredSlot, slot >= 0, slot < top5.count else { return nil }
        return top5[slot]
    }

    var body: some View {
        BentoCard(
            borderColor: PanelPalette.memAccent,
            topGlow: PanelPalette.memGlow,
            isAlert: isAlert,
            isHovered: isHovered
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 5) {
                    Text("MEM")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PanelPalette.textPrimary)
                    if isAlert { AlertPulseDot() }
                    Spacer()
                    Text(verbatim: PanelFormat.percent(stats.usedFraction))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isAlert ? PanelPalette.alertAccent : PanelPalette.textPrimary)
                }

                ThinMetricBar(
                    fraction: stats.usedFraction,
                    tint: isAlert ? PanelPalette.alertAccent : PanelPalette.memAccent
                )

                ProcessMondrianGrid(
                    processes: top5,
                    mode: .memory(totalBytes: stats.totalBytes),
                    hoveredSlot: $hoveredSlot
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 2)

                // 悬停在某个内存进程块上时，底部栏实时切换为该进程详情；移开恢复已用/总内存与压力点。
                Group {
                    if let proc = hoveredProcess {
                        hoveredMemoryFooter(proc)
                    } else {
                        HStack(spacing: 4) {
                            Text(verbatim: PanelFormat.memoryRatio(used: stats.usedBytes, total: stats.totalBytes))
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(PanelPalette.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            memoryPressureBadge
                        }
                    }
                }
                .frame(height: 13)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredSlot = nil }
        }
        .animation(.easeOut(duration: 0.14), value: hoveredSlot)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Memory \(PanelFormat.percent(stats.usedFraction))"))
    }

    private func hoveredMemoryFooter(_ proc: ProcessUsage) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(PanelPalette.memAccent)
                .frame(width: 4.5, height: 4.5)
            Text(verbatim: proc.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 3)
            Text(verbatim: PanelFormat.bytes(proc.memoryBytes))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(PanelPalette.segOrange)
            Text(verbatim: "·")
                .font(.system(size: 8.5))
                .foregroundStyle(PanelPalette.textMuted)
            Text(verbatim: PanelFormat.cpuPercent(proc.cpu))
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
        }
        .lineLimit(1)
    }

    private var memoryPressureBadge: some View {
        let color: Color = switch stats.pressure {
        case .normal: PanelPalette.cpuAccent
        case .warning: PanelPalette.segYellow
        case .critical: PanelPalette.alertAccent
        }
        let swapActive = stats.swapUsedBytes > 64 << 20
        return HStack(spacing: 3) {
            if swapActive {
                Text(verbatim: "SWAP")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(PanelPalette.segOrange)
            }
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
        }
        .help(Text("Swap: \(PanelFormat.bytes(stats.swapUsedBytes))"))
    }
}

// MARK: - 3. STORAGE Card

private enum StorageCategory: CaseIterable, Equatable {
    case system, apps, user, cache, free

    var title: LocalizedStringKey {
        switch self {
        case .system: "system"
        case .apps: "Apps"
        case .user: "user"
        case .cache: "cache"
        case .free: "free"
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .apps: "Apps"
        case .user: "User"
        case .cache: "Cache"
        case .free: "Free"
        }
    }

    var color: Color {
        switch self {
        case .system: PanelPalette.segGreen
        case .apps: PanelPalette.segOrange
        case .user: PanelPalette.segBlue
        case .cache: PanelPalette.segYellow
        case .free: PanelPalette.segFree
        }
    }

    func bytes(in breakdown: DiskBreakdown) -> UInt64 {
        switch self {
        case .system: breakdown.systemBytes
        case .apps: breakdown.appsBytes
        case .user: breakdown.userBytes
        case .cache: breakdown.cacheBytes
        case .free: breakdown.freeBytes
        }
    }
}

struct StorageCard: View {
    let stats: DiskStats
    var onOpenAnalyze: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var hoveredCategory: StorageCategory?

    private var isAlert: Bool { stats.usedFraction >= MetricThreshold.disk }

    private var breakdown: DiskBreakdown {
        if stats.breakdown.totalBytes > 0 {
            return stats.breakdown
        }
        let used = stats.usedBytes
        return DiskBreakdown(
            systemBytes: UInt64(Double(used) * 0.24),
            appsBytes: UInt64(Double(used) * 0.22),
            userBytes: UInt64(Double(used) * 0.38),
            cacheBytes: UInt64(Double(used) * 0.16),
            freeBytes: stats.freeBytes)
    }

    var body: some View {
        Button {
            onOpenAnalyze?()
        } label: {
            BentoCard(
                borderColor: PanelPalette.storageBorder,
                topGlow: PanelPalette.storageGlow,
                isAlert: isAlert,
                isHovered: isHovered
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text("STORAGE")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(PanelPalette.textPrimary)
                        if isAlert { AlertPulseDot() }
                        Spacer()
                        Text(verbatim: PanelFormat.percent(stats.usedFraction))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isAlert ? PanelPalette.alertAccent : PanelPalette.textSecondary)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(verbatim: PanelFormat.compactStorage(stats.freeBytes))
                            .font(.system(size: 22, weight: .medium).monospacedDigit())
                            .foregroundStyle(isAlert ? PanelPalette.alertAccent : PanelPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Free")
                            Text("of \(PanelFormat.compactStorage(stats.totalBytes))")
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textSecondary)
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }

                    // 实时磁盘读写速率条：合并自原 Disk I/O 模块，直接展示 R / W 吞吐。
                    HStack(spacing: 8) {
                        diskIORateItem(
                            prefix: "R",
                            bytesPerSecond: stats.readBytesPerSecond,
                            color: PanelPalette.cpuAccent
                        )
                        diskIORateItem(
                            prefix: "W",
                            bytesPerSecond: stats.writeBytesPerSecond,
                            color: PanelPalette.segOrange
                        )
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    // 20×5 = 100 格精确百分比扇区图（每格 = 1%），独立封装并按 breakdown 等值跳过磁盘 R/W 引发的无关重绘。
                    StorageSectorGrid(
                        breakdown: breakdown,
                        hoveredCategory: hoveredCategory
                    ) { next in
                        if hoveredCategory != next {
                            hoveredCategory = next
                        }
                    }
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 1)

                    // 悬停某分类时，底部图例平滑切换为该分类的精确容量与占比；移开恢复五色图例。
                    Group {
                        if let category = hoveredCategory {
                            hoveredCategoryFooter(category)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(StorageCategory.allCases, id: \.self) { category in
                                    legendDot(category)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(height: 13)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredCategory = nil }
        }
        .animation(.easeOut(duration: 0.14), value: hoveredCategory)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Storage \(PanelFormat.compactStorage(stats.freeBytes)) free of \(PanelFormat.compactStorage(stats.totalBytes))")
        )
    }

    private func diskIORateItem(prefix: String, bytesPerSecond: Double, color: Color) -> some View {
        let active = bytesPerSecond >= 1_024
        return HStack(spacing: 3) {
            Circle()
                .fill(active ? color : PanelPalette.inactivePixel)
                .frame(width: 4.5, height: 4.5)
            Text(verbatim: prefix)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(active ? color : PanelPalette.textMuted)
            Text(verbatim: PanelFormat.rate(bytesPerSecond))
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
        }
    }

    private func hoveredCategoryFooter(_ category: StorageCategory) -> some View {
        let bytes = category.bytes(in: breakdown)
        let total = max(1, Double(breakdown.totalBytes))
        let pct = Int((Double(bytes) / total * 100).rounded())

        return HStack(spacing: 4) {
            Circle()
                .fill(category.color)
                .frame(width: 4.5, height: 4.5)
            Text(category.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelPalette.textPrimary)
            Spacer(minLength: 3)
            Text(verbatim: PanelFormat.bytes(bytes))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(category == .free ? PanelPalette.textPrimary : category.color)
            Text(verbatim: "(\(pct)%)")
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(PanelPalette.textMuted)
        }
        .lineLimit(1)
    }

    private func legendDot(_ category: StorageCategory) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(category.color)
                .frame(width: 3.5, height: 3.5)
            Text(category.title)
                .font(.system(size: 7.8, weight: .regular))
                .foregroundStyle(PanelPalette.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .onHover { hovering in
            if hovering {
                hoveredCategory = category
            } else if hoveredCategory == category {
                hoveredCategory = nil
            }
        }
    }

    fileprivate static func make100SectorCells(breakdown: DiskBreakdown) -> [StorageCategory] {
        let total = max(1, Double(breakdown.totalBytes))
        let exact = StorageCategory.allCases.map { cat -> (StorageCategory, Double) in
            (cat, Double(cat.bytes(in: breakdown)) / total * 100.0)
        }
        var counts = exact.map { Int(floor($0.1)) }
        var remainder = 100 - counts.reduce(0, +)
        let sortedByFrac = exact.indices.sorted {
            (exact[$0].1 - floor(exact[$0].1)) > (exact[$1].1 - floor(exact[$1].1))
        }
        for idx in sortedByFrac where remainder > 0 {
            counts[idx] += 1
            remainder -= 1
        }
        var cells: [StorageCategory] = []
        cells.reserveCapacity(100)
        for (cat, count) in zip(StorageCategory.allCases, counts) {
            cells.append(contentsOf: repeatElement(cat, count: max(0, count)))
        }
        while cells.count < 100 { cells.append(.free) }
        return Array(cells.prefix(100))
    }
}

private struct StorageSectorGrid: View, Equatable {
    let breakdown: DiskBreakdown
    let hoveredCategory: StorageCategory?
    let onHoverCategory: (StorageCategory?) -> Void

    private let cols = 20
    private let rows = 5

    nonisolated static func == (lhs: StorageSectorGrid, rhs: StorageSectorGrid) -> Bool {
        lhs.breakdown == rhs.breakdown && lhs.hoveredCategory == rhs.hoveredCategory
    }

    var body: some View {
        let cells = StorageCard.make100SectorCells(breakdown: breakdown)
        GeometryReader { proxy in
            Canvas { context, size in
                let gap: CGFloat = 1.8
                let cellW = max(2, (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols))
                let cellH = max(2, (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))

                // 按 5 个分类合并 Path，只需最多 5 次 context.fill 即可画完 100 格。
                var paths: [StorageCategory: Path] = [:]
                for index in 0..<(cols * rows) {
                    let row = index / cols
                    let col = index % cols
                    let x = CGFloat(col) * (cellW + gap)
                    let y = CGFloat(row) * (cellH + gap)
                    let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                    let category = index < cells.count ? cells[index] : .free
                    paths[category, default: Path()].addRoundedRect(
                        in: rect, cornerSize: CGSize(width: 1.2, height: 1.2))
                }
                for category in StorageCategory.allCases {
                    guard let path = paths[category], !path.isEmpty else { continue }
                    let color = Self.cellColor(for: category, hovered: hoveredCategory)
                    context.fill(path, with: .color(color))
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard proxy.size.width > 0, proxy.size.height > 0 else { return }
                    let col = min(cols - 1, max(0, Int((location.x / proxy.size.width) * CGFloat(cols))))
                    let row = min(rows - 1, max(0, Int((location.y / proxy.size.height) * CGFloat(rows))))
                    let idx = row * cols + col
                    if idx >= 0 && idx < cells.count {
                        onHoverCategory(cells[idx])
                    }
                case .ended:
                    onHoverCategory(nil)
                }
            }
        }
    }

    private static func cellColor(for category: StorageCategory, hovered: StorageCategory?) -> Color {
        if let hovered {
            if category == hovered {
                return category == .free
                    ? PanelPalette.segFree
                    : category.color
            }
            return category == .free
                ? PanelPalette.inactivePixel.opacity(0.45)
                : category.color.opacity(0.24)
        }
        return category == .free
            ? PanelPalette.inactivePixel.opacity(0.85)
            : category.color.opacity(0.90)
    }
}


private struct PortRowPill: View {
    let item: ListeningPort
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        let color = NetworkPortsCard.categoryColor(item.category)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)

                Text(verbatim: ":\(item.port)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(PanelPalette.textPrimary)
                    .frame(width: 38, alignment: .leading)

                Text(verbatim: item.processName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                if isHovered && item.isWebOpenable {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                } else {
                    Text(verbatim: NetworkPortsCard.categoryTag(item.category))
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(color.opacity(0.85))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 18.5)
            .background {
                shape.fill(isHovered ? color.opacity(0.16) : PanelPalette.pillBackground)
            }
            .overlay {
                shape.strokeBorder(
                    isHovered ? color.opacity(0.60) : PanelPalette.pillBorder,
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .help(portTooltipText)
    }

    private var portTooltipText: Text {
        let portStr = String(item.port)
        let pidStr = String(item.pid)
        if item.isWebOpenable {
            return Text(
                "\(item.processName) · \(item.bindAddress):\(portStr) (PID \(pidStr))\nClick to open http://localhost:\(portStr)"
            )
        }
        return Text(verbatim: "\(item.processName) · \(item.bindAddress):\(portStr) (PID \(pidStr))")
    }
}


// MARK: - 5. BATTERY Card

struct BatteryCard: View {
    let stats: BatteryStats?
    var power: PowerStats = .empty

    @State private var isHovered = false
    @State private var hoveredCell: Int?

    private var isAlert: Bool {
        guard let stats else { return false }
        return PanelFormat.batteryIsAlert(level: stats.level, isCharging: stats.isCharging)
    }

    var body: some View {
        BentoCard(
            borderColor: PanelPalette.batteryAccent,
            topGlow: PanelPalette.batteryGlow,
            isAlert: isAlert,
            isHovered: isHovered
        ) {
            if let stats {
                batteryContent(stats)
            } else {
                desktopACContent
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredCell = nil }
        }
        .animation(.easeOut(duration: 0.14), value: hoveredCell)
        .accessibilityElement(children: .combine)
    }

    private func batteryContent(_ stats: BatteryStats) -> some View {
        let cellColor = Self.levelColor(level: stats.level, isCharging: stats.isCharging)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("BATTERY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PanelPalette.textPrimary)
                if isAlert { AlertPulseDot() }
                Spacer(minLength: 2)
                if power.isExternalConnected, let rated = power.adapterRatedWatts {
                    Text(verbatim: "\(rated)W PD")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PanelPalette.segTeal)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(PanelPalette.segTeal.opacity(0.14), in: Capsule())
                }
                batteryBadge(level: stats.level, isCharging: stats.isCharging, fillColor: cellColor)
            }

            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: PanelFormat.percent(stats.level))
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                        .foregroundStyle(isAlert ? PanelPalette.alertAccent : PanelPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let health = stats.health {
                        Text("Health \(PanelFormat.percent(health))")
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    } else {
                        Text(verbatim: PanelFormat.batteryStatusText(isCharging: stats.isCharging))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
                Spacer(minLength: 2)
                batteryCellGrid(stats: stats, fillColor: cellColor)
            }

            // 合并自 Power 的紧凑实时功耗条（无柱状图）：整机功耗 + 适配器实时输入/放电功率。
            if power.systemWatts != nil || power.adapterInputWatts != nil {
                HStack(spacing: 5) {
                    HStack(spacing: 2.5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(power.isExternalConnected ? PanelPalette.segTeal : PanelPalette.thermalAccent)
                        Text(verbatim: BatteryCard.formatWatts(power.systemWatts))
                            .font(.system(size: 9.2, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PanelPalette.textPrimary)
                    }
                    Spacer(minLength: 2)
                    if let input = power.adapterInputWatts, power.isExternalConnected {
                        Text("In \(BatteryCard.formatCompactWatts(input))")
                            .font(.system(size: 8.8, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.segTeal)
                    } else if let bat = power.batteryWatts, bat < -0.1 {
                        Text("Bat \(BatteryCard.formatCompactWatts(abs(bat)))")
                            .font(.system(size: 8.8, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.textSecondary)
                    }
                }
                .lineLimit(1)
                .frame(height: 12)
            }

            Spacer(minLength: 0)

            // 底部栏：平时显示供电状态/循环次数 + 预计时长；悬停任意电芯或卡片时显示详细电源与循环信息。
            Group {
                if let cell = hoveredCell {
                    hoveredCellFooter(cell: cell, stats: stats, color: cellColor)
                } else {
                    restingFooter(stats: stats, color: cellColor)
                }
            }
            .frame(height: 13)
        }
    }

    private func restingFooter(stats: BatteryStats, color: Color) -> some View {
        let statusLabel: String = if stats.isCharging {
            L10n.text("Charging")
        } else if stats.isPluggedIn {
            L10n.text("Plugged")
        } else if let cycles = stats.cycleCount {
            L10n.text("\(cycles) cyc")
        } else {
            L10n.text("Battery")
        }

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text(verbatim: statusLabel)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let time = PanelFormat.batteryTimeRemaining(stats.timeRemainingMinutes) {
                HStack(spacing: 1.5) {
                    Image(systemName: stats.isCharging ? "bolt.fill" : "clock")
                        .font(.system(size: 7.5))
                        .foregroundStyle(stats.isCharging ? PanelPalette.segYellow : PanelPalette.textSecondary)
                    Text(verbatim: time)
                }
                .lineLimit(1)
            } else if stats.isCharging || stats.isPluggedIn, let cycles = stats.cycleCount {
                Text("\(cycles) cyc")
                    .lineLimit(1)
            }
        }
        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
        .foregroundStyle(PanelPalette.textSecondary)
    }

    private func hoveredCellFooter(cell: Int, stats: BatteryStats, color: Color) -> some View {
        let low = cell * 25
        let high = (cell + 1) * 25
        let source = stats.isPluggedIn || stats.isCharging ? L10n.text("AC") : L10n.text("BAT")
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(verbatim: "\(low)–\(high)%")
                .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(PanelPalette.textPrimary)
            Spacer(minLength: 2)
            if let cycles = stats.cycleCount {
                Text("\(source) · \(cycles) cyc")
                    .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textSecondary)
            } else {
                Text(verbatim: source)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(PanelPalette.textSecondary)
            }
        }
        .lineLimit(1)
    }

    private var desktopACContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("POWER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PanelPalette.textPrimary)
                Spacer()
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.batteryAccent)
            }
            Spacer(minLength: 0)
            Text("AC")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(PanelPalette.textPrimary)
            Text("Plugged In")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(PanelPalette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func batteryBadge(level: Double, isCharging: Bool, fillColor: Color) -> some View {
        HStack(spacing: 2) {
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PanelPalette.segYellow)
            }
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .strokeBorder(fillColor.opacity(0.8), lineWidth: 1)
                        .frame(width: 18, height: 9)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(fillColor)
                        .frame(width: max(2, 14 * min(1, max(0, level))), height: 5)
                        .padding(.leading, 2)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(fillColor.opacity(0.8))
                    .frame(width: 1.5, height: 4)
            }
        }
    }

    /// 真实 4 电芯分格（每格严格 25%：左下 0–25%、右下 25–50%、左上 50–75%、右上 75–100%），
    /// 局部按精确比例从底向上填充；闪电图标仅在真实充电时点亮。
    private func batteryCellGrid(stats: BatteryStats, fillColor: Color) -> some View {
        let level = min(1, max(0, stats.level))
        func cellFill(_ index: Int) -> Double {
            min(1, max(0, (level - Double(index) * 0.25) / 0.25))
        }

        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                cellTile(index: 2, fill: cellFill(2), color: fillColor, isCharging: stats.isCharging)
                cellTile(index: 3, fill: cellFill(3), color: fillColor, isCharging: stats.isCharging)
            }
            HStack(spacing: 3) {
                cellTile(index: 0, fill: cellFill(0), color: fillColor, isCharging: stats.isCharging)
                cellTile(index: 1, fill: cellFill(1), color: fillColor, isCharging: stats.isCharging)
            }
        }
    }

    private func cellTile(index: Int, fill: Double, color: Color, isCharging: Bool) -> some View {
        let isCellHovered = hoveredCell == index
        let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        let showBolt = isCharging && (fill > 0.05 || index == 0)

        return ZStack(alignment: .bottom) {
            shape.fill(PanelPalette.inactivePixel)

            if fill > 0.01 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 15 * fill)
            }

            if showBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(fill > 0.45 ? Color.black.opacity(0.78) : PanelPalette.segYellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 18, height: 15)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isCellHovered ? Color.white.opacity(0.85) : Color.white.opacity(fill > 0.01 ? 0.14 : 0.06),
                lineWidth: isCellHovered ? 1 : 0.6
            )
        }
        .onHover { hovering in
            if hovering {
                hoveredCell = index
            } else if hoveredCell == index {
                hoveredCell = nil
            }
        }
    }

    private static func levelColor(level: Double, isCharging: Bool) -> Color {
        if isCharging {
            return PanelPalette.batteryAccent
        }
        if level < PanelFormat.batteryAlertLevel {
            return PanelPalette.alertAccent
        }
        if level < 0.45 {
            return PanelPalette.segYellow
        }
        return PanelPalette.segGreen
    }
}

// MARK: - 5b. 纯只读 THERMAL 卡（第三行右侧，CPU / GPU / SSD 三路温度进度条 + 风扇转速）

struct CompactThermalCard: View {
    let stats: ThermalStats
    var history: [Double] = []

    @State private var isHovered = false
    @State private var hoveredSensor: String?

    private var hottestCelsius: Double? {
        [stats.temperatureCelsius, stats.gpuTemperatureCelsius, stats.ssdTemperatureCelsius]
            .compactMap { $0 }
            .max()
    }

    private var isAlert: Bool {
        (hottestCelsius ?? 0) >= MetricThreshold.thermalCelsius
    }

    private var stateColor: Color {
        Self.tempColor(hottestCelsius)
    }

    private var stateLabel: LocalizedStringKey {
        guard let t = hottestCelsius else { return "--" }
        if t >= MetricThreshold.thermalCelsius { return "HOT" }
        if t >= 62 { return "WARM" }
        return "COOL"
    }

    private var peakTemp: Double? {
        let histMax = history.max()
        switch (stats.temperatureCelsius, histMax) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    var body: some View {
        BentoCard(
            borderColor: PanelPalette.thermalAccent,
            topGlow: PanelPalette.thermalGlow,
            isAlert: isAlert,
            isHovered: isHovered
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("TEMPERATURE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(PanelPalette.textPrimary)
                        .lineLimit(1)
                    if isAlert { AlertPulseDot() }
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isAlert ? PanelPalette.alertAccent : stateColor)
                            .frame(width: 4.5, height: 4.5)
                        Text(stateLabel)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(stateColor)
                    }
                }

                Spacer(minLength: 0)

                // CPU / GPU / SSD 三路直观温度条（20°C ~ 100°C 刻度，温区渐变着色）
                VStack(spacing: 5) {
                    sensorGaugeRow(label: "CPU", celsius: stats.temperatureCelsius, warnAt: 62, hotAt: MetricThreshold.thermalCelsius)
                    sensorGaugeRow(label: "GPU", celsius: stats.gpuTemperatureCelsius, warnAt: 62, hotAt: MetricThreshold.thermalCelsius)
                    sensorGaugeRow(label: "SSD", celsius: stats.ssdTemperatureCelsius, warnAt: 52, hotAt: 68)
                }

                Spacer(minLength: 0)

                // 底部：左侧风扇转速，右侧会话峰值温度。
                HStack(spacing: 4) {
                    Image(systemName: stats.fanCount == 0 && stats.fanRPM == nil ? "wind" : "fan.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle((stats.fanRPM ?? 0) > 0 ? PanelPalette.thermalAccent : PanelPalette.textSecondary)
                    Text(verbatim: PanelFormat.fanRPM(stats))
                        .font(.system(size: 9.2, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let peak = peakTemp {
                        Text("Peak \(PanelFormat.temperature(peak))")
                            .font(.system(size: 8.8, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(height: 13)
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredSensor = nil }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Thermal CPU \(PanelFormat.temperature(stats.temperatureCelsius)), \(PanelFormat.fanRPM(stats))")
        )
    }

    private func sensorGaugeRow(
        label: String,
        celsius: Double?,
        warnAt: Double,
        hotAt: Double
    ) -> some View {
        let isRowHovered = hoveredSensor == label
        let dimmed = hoveredSensor != nil && !isRowHovered
        let color = Self.tempColor(celsius, warnAt: warnAt, hotAt: hotAt)
        let fraction: Double = {
            guard let t = celsius else { return 0 }
            return min(1, max(0.06, (t - 20.0) / 80.0))
        }()

        return HStack(spacing: 6) {
            Text(verbatim: label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isRowHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                .frame(width: 24, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PanelPalette.inactivePixel.opacity(0.65))
                    if celsius != nil {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.75), color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(5, proxy.size.width * fraction))
                    }
                }
            }
            .frame(height: 5.5)

            Text(verbatim: PanelFormat.temperature(celsius))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(celsius != nil ? PanelPalette.textPrimary : PanelPalette.textMuted)
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(dimmed ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredSensor = label
            } else if hoveredSensor == label {
                hoveredSensor = nil
            }
        }
    }

    private static func tempColor(
        _ temp: Double?,
        warnAt: Double = 62,
        hotAt: Double = MetricThreshold.thermalCelsius
    ) -> Color {
        guard let t = temp else { return PanelPalette.textMuted }
        if t >= hotAt { return PanelPalette.alertAccent }
        if t >= warnAt { return PanelPalette.thermalAccent }
        return PanelPalette.cpuAccent
    }
}


// MARK: - 6. NETWORK + PORTS Card

struct NetworkPortsCard: View {
    let stats: NetworkStats
    let ports: [ListeningPort]
    var onOpenNetwork: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var hoveredPort: ListeningPort?

    private var visiblePorts: [ListeningPort] {
        Array(ports.prefix(4))
    }

    var body: some View {
        BentoCard(
            borderColor: PanelPalette.networkAccent,
            topGlow: PanelPalette.networkGlow,
            isHovered: isHovered
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("NETWORK")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(PanelPalette.textPrimary)
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        Circle()
                            .fill(ports.isEmpty ? PanelPalette.textMuted : PanelPalette.segTeal)
                            .frame(width: 4, height: 4)
                        Group {
                            if ports.isEmpty {
                                Text("IDLE")
                            } else {
                                Text("\(ports.count) PORTS")
                            }
                        }
                        .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ports.isEmpty ? PanelPalette.textMuted : PanelPalette.segTeal)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        (ports.isEmpty ? PanelPalette.textMuted : PanelPalette.segTeal).opacity(0.14),
                        in: Capsule()
                    )
                }

                // 实时下行 / 上行速率
                HStack(spacing: 10) {
                    rateItem(arrow: "↓", bytesPerSecond: stats.downBytesPerSecond, color: PanelPalette.networkAccent)
                    rateItem(arrow: "↑", bytesPerSecond: stats.upBytesPerSecond, color: PanelPalette.memAccent)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                // 智能筛选后的端口占用表
                if visiblePorts.isEmpty {
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Image(systemName: "network.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(PanelPalette.textMuted)
                        Text("No active dev ports")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 2.5) {
                        ForEach(visiblePorts) { item in
                            PortRowPill(
                                item: item,
                                isHovered: hoveredPort?.id == item.id
                            ) {
                                openInBrowser(item)
                            }
                            .onHover { hovering in
                                if hovering {
                                    hoveredPort = item
                                } else if hoveredPort?.id == item.id {
                                    hoveredPort = nil
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                // 底部栏：悬停端口时展示 PID 与地址；平时展示分类图例与余量。
                Group {
                    if let item = hoveredPort {
                        hoveredPortFooter(item)
                    } else {
                        restingFooter
                    }
                }
                .frame(height: 13)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onOpenNetwork?()
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering { hoveredPort = nil }
        }
        .animation(.easeOut(duration: 0.14), value: hoveredPort?.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "Network down \(PanelFormat.rate(stats.downBytesPerSecond)), up \(PanelFormat.rate(stats.upBytesPerSecond)), \(ports.count) active ports"
            )
        )
    }

    private func rateItem(arrow: String, bytesPerSecond: Double, color: Color) -> some View {
        HStack(spacing: 2.5) {
            Text(verbatim: arrow)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: PanelFormat.rate(bytesPerSecond))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(PanelPalette.textPrimary)
        }
    }

    private func hoveredPortFooter(_ item: ListeningPort) -> some View {
        let color = NetworkPortsCard.categoryColor(item.category)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            Text(verbatim: "PID \(item.pid) · \(item.bindAddress)")
                .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if item.isWebOpenable {
                Text("Open ↗")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Text(verbatim: "TCP")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(PanelPalette.textMuted)
            }
        }
        .lineLimit(1)
    }

    private var restingFooter: some View {
        HStack(spacing: 5) {
            portLegendDot(PanelPalette.segTeal, "Web")
            portLegendDot(PanelPalette.cpuAccent, "AI")
            portLegendDot(PanelPalette.segYellow, "DB")
            portLegendDot(PanelPalette.networkAccent, "Proxy")
            Spacer(minLength: 0)
            if ports.count > visiblePorts.count {
                Text(verbatim: "+\(ports.count - visiblePorts.count)")
                    .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(PanelPalette.textSecondary)
            }
        }
        .lineLimit(1)
    }

    private func portLegendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 3.5, height: 3.5)
            Text(label)
                .font(.system(size: 7.8, weight: .regular))
                .foregroundStyle(PanelPalette.textSecondary)
        }
    }

    private func openInBrowser(_ item: ListeningPort) {
        guard item.isWebOpenable,
            let url = URL(string: "http://localhost:\(item.port)")
        else {
            onOpenNetwork?()
            return
        }
        NSWorkspace.shared.open(url)
    }
}


extension BatteryCard {
    static func formatWatts(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "-- W" }
        return String(format: "%.1f W", watts)
    }

    static func formatCompactWatts(_ watts: Double) -> String {
        watts >= 100 ? String(format: "%.0fW", watts) : String(format: "%.1fW", watts)
    }
}

extension NetworkPortsCard {
    static func categoryColor(_ category: PortCategory) -> Color {
        switch category {
        case .web: PanelPalette.segTeal
        case .ai: PanelPalette.cpuAccent
        case .database: PanelPalette.segYellow
        case .proxy: PanelPalette.networkAccent
        case .other: PanelPalette.textSecondary
        }
    }

    static func categoryTag(_ category: PortCategory) -> String {
        switch category {
        case .web: "WEB"
        case .ai: "AI"
        case .database: "DB"
        case .proxy: "PRX"
        case .other: "TCP"
        }
    }
}
