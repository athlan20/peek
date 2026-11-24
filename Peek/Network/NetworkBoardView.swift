import SwiftUI

/// 方案一「按进程分组的整齐 Bento 方块拼图」：
/// 外层采用跨列对齐的 Bento 栅格，端口多的进程占更大跨度（2 列 / 3 列 / 整行），单端口进程占 1 列；
/// 内层所有端口瓷砖保持严格等宽等高、居中饱满排布，杜绝细长竖条与空洞拉伸。
struct NetworkBoardView: View {
    let groups: [NetworkProcessGroup]
    let selectedPortID: String?
    let onSelect: (ListeningPort) -> Void
    let onOpen: (ListeningPort) -> Void
    let onCopy: (ListeningPort) -> Void
    let onReveal: (ListeningPort) -> Void
    let onKill: (ListeningPort) -> Void

    private let outerPadding: CGFloat = 12
    private let gridGap: CGFloat = 10
    private let tileHeight: CGFloat = 76
    private let innerGap: CGFloat = 8
    private let clusterPadding: CGFloat = 9
    private let headerHeight: CGFloat = 18
    private let headerSpacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - outerPadding * 2)
            let totalCols = NetworkPortGroups.totalColumns(forWidth: contentWidth, gap: gridGap)
            let rows = NetworkPortGroups.bentoRows(for: groups, totalColumns: totalCols)
            let unitWidth = max(
                0,
                (contentWidth - gridGap * CGFloat(totalCols - 1)) / CGFloat(totalCols)
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gridGap) {
                    ForEach(rows) { row in
                        let innerRows = row.maxInnerRows
                        let rowHeight =
                            clusterPadding * 2
                            + headerHeight
                            + headerSpacing
                            + tileHeight * CGFloat(innerRows)
                            + innerGap * CGFloat(max(0, innerRows - 1))

                        HStack(alignment: .top, spacing: gridGap) {
                            ForEach(row.slots) { slot in
                                let slotWidth =
                                    unitWidth * CGFloat(slot.span)
                                    + gridGap * CGFloat(max(0, slot.span - 1))

                                ProcessClusterView(
                                    slot: slot,
                                    tileHeight: tileHeight,
                                    innerGap: innerGap,
                                    clusterPadding: clusterPadding,
                                    headerHeight: headerHeight,
                                    headerSpacing: headerSpacing,
                                    selectedPortID: selectedPortID,
                                    onSelect: onSelect,
                                    onOpen: onOpen,
                                    onCopy: onCopy,
                                    onReveal: onReveal,
                                    onKill: onKill
                                )
                                .frame(width: slotWidth, height: rowHeight)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(outerPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .animation(.easeOut(duration: 0.22), value: groups.map { "\($0.id):\($0.ports.count)" })
        }
    }
}

// MARK: - 外层进程大块容器

private struct ProcessClusterView: View {
    @Environment(\.colorScheme) private var colorScheme

    let slot: NetworkBentoSlot
    let tileHeight: CGFloat
    let innerGap: CGFloat
    let clusterPadding: CGFloat
    let headerHeight: CGFloat
    let headerSpacing: CGFloat
    let selectedPortID: String?
    let onSelect: (ListeningPort) -> Void
    let onOpen: (ListeningPort) -> Void
    let onCopy: (ListeningPort) -> Void
    let onReveal: (ListeningPort) -> Void
    let onKill: (ListeningPort) -> Void

    private var group: NetworkProcessGroup { slot.group }

    private var accent: Color {
        NetworkPortsCard.categoryColor(group.dominantCategory)
    }

    var body: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: innerGap),
            count: max(1, slot.innerColumns)
        )

        VStack(alignment: .leading, spacing: headerSpacing) {
            clusterHeader

            LazyVGrid(columns: columns, spacing: innerGap) {
                ForEach(group.ports) { item in
                    PortBlockTile(
                        item: item,
                        showPID: group.pids.count > 1,
                        isSelected: item.id == selectedPortID
                    )
                    .frame(height: tileHeight)
                    .onTapGesture(count: 2) {
                        onSelect(item)
                        if item.isWebOpenable {
                            onOpen(item)
                        } else {
                            onCopy(item)
                        }
                    }
                    .onTapGesture {
                        onSelect(item)
                    }
                    .contextMenu {
                        if item.isWebOpenable {
                            Button {
                                onOpen(item)
                            } label: {
                                Label("Open in Browser", systemImage: "arrow.up.right.square")
                            }
                        }
                        Button {
                            onCopy(item)
                        } label: {
                            Label("Copy Address", systemImage: "doc.on.doc")
                        }
                        if item.executablePath != nil {
                            Button {
                                onReveal(item)
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            onKill(item)
                        } label: {
                            Label("Kill Process", systemImage: "xmark.octagon")
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(clusterPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape
                .fill(isLight ? Color.white.opacity(0.76) : Color.white.opacity(0.03))
                .overlay {
                    LinearGradient(
                        colors: [
                            accent.opacity(isLight ? 0.10 : 0.14),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }
        }
        .overlay {
            shape.strokeBorder(
                accent.opacity(isLight ? 0.28 : 0.30),
                lineWidth: 1
            )
        }
        .clipShape(shape)
    }

    private var clusterHeader: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(verbatim: group.processName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(PanelPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            if group.pids.count == 1, let pid = group.pids.first {
                Text(verbatim: "PID \(pid)")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
            } else if group.pids.count > 1 {
                Text("\(group.pids.count) PIDs")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(verbatim: "\(group.ports.count)")
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(accent.opacity(0.14), in: Capsule())
        }
        .frame(height: headerHeight)
    }
}

// MARK: - 内层等大居中端口瓷砖

private struct PortBlockTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: ListeningPort
    let showPID: Bool
    let isSelected: Bool

    @State private var isHovered = false

    private var categoryColor: Color {
        NetworkPortsCard.categoryColor(item.category)
    }

    var body: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        ZStack {
            // 中央视觉焦点：大号等宽端口号 + 监听地址（与 Analyze / Uninstall 方块居中质感一致）
            VStack(spacing: 3) {
                Text(verbatim: ":\(item.port)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(PanelPalette.treemapTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 4) {
                    Text(verbatim: item.bindAddress)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.treemapTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if showPID {
                        Text(verbatim: "· #\(item.pid)")
                            .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                            .foregroundStyle(PanelPalette.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)

            // 顶角轻巧元信息：左上分类胶囊，右上活跃连接 / 对外暴露图标
            VStack {
                HStack(spacing: 4) {
                    Text(verbatim: NetworkPortsCard.categoryTag(item.category))
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            categoryColor.opacity(isLight ? 0.16 : 0.22),
                            in: Capsule()
                        )

                    Spacer(minLength: 2)

                    if item.establishedCount > 0 {
                        HStack(spacing: 2.5) {
                            Circle()
                                .fill(PanelPalette.segGreen)
                                .frame(width: 4.5, height: 4.5)
                            Text(verbatim: "\(item.establishedCount)")
                                .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(PanelPalette.treemapTextSecondary)
                        }
                    } else if item.isExposedExternally {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(PanelPalette.treemapTextSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(tileBaseFill(isLight: isLight))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: isLight
                                ? [Color.white.opacity(isHovered ? 0.55 : 0.35), Color.clear]
                                : [Color.white.opacity(isHovered ? 0.16 : 0.08), Color.clear, Color.black.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        }
        .overlay {
            shape.strokeBorder(
                isSelected
                    ? PanelPalette.treemapSelectionBorder
                    : categoryColor.opacity(isHovered ? 0.78 : (isLight ? 0.34 : 0.38)),
                lineWidth: isSelected ? 1.8 : (isHovered ? 1.1 : 0.85)
            )
        }
        .clipShape(shape)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .help(tooltipText)
    }

    private func tileBaseFill(isLight: Bool) -> Color {
        if isLight {
            return categoryColor.opacity(isSelected ? 0.24 : (isHovered ? 0.20 : 0.14))
        }
        return categoryColor.opacity(isSelected ? 0.30 : (isHovered ? 0.24 : 0.17))
    }

    private var tooltipText: String {
        var lines = [
            ":\(item.port)  \(item.processName) (PID \(item.pid))",
            "\(item.bindAddress) · \(NetworkPortsCard.categoryTag(item.category))",
        ]
        if item.establishedCount > 0 {
            lines.append("Active connections: \(item.establishedCount)")
        }
        if let path = item.executablePath {
            lines.append(path)
        }
        return lines.joined(separator: "\n")
    }
}
