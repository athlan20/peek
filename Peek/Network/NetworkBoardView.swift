import SwiftUI

/// 方案一「按进程分组的方块拼图」：
/// 外层按进程分组并使用 `TreemapLayout.squarify` 按端口数量分配面积；
/// 内层每个端口以等大、清晰可读的圆角发光瓷砖排布。
struct NetworkBoardView: View {
    let groups: [NetworkProcessGroup]
    let selectedPortID: String?
    let onSelect: (ListeningPort) -> Void
    let onOpen: (ListeningPort) -> Void
    let onCopy: (ListeningPort) -> Void
    let onReveal: (ListeningPort) -> Void
    let onKill: (ListeningPort) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let rects = TreemapLayout.squarify(groups.map(\.treemapWeight), in: bounds)
            let gap: CGFloat = 6

            ZStack(alignment: .topLeading) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    let raw = rects[index]
                    let rect = CGRect(
                        x: raw.minX.rounded(),
                        y: raw.minY.rounded(),
                        width: raw.maxX.rounded() - raw.minX.rounded(),
                        height: raw.maxY.rounded() - raw.minY.rounded()
                    )
                    let effectiveGap = (rect.width > gap * 3 && rect.height > gap * 3) ? gap : 2
                    ProcessClusterView(
                        group: group,
                        selectedPortID: selectedPortID,
                        onSelect: onSelect,
                        onOpen: onOpen,
                        onCopy: onCopy,
                        onReveal: onReveal,
                        onKill: onKill
                    )
                    .frame(
                        width: max(0, rect.width - effectiveGap),
                        height: max(0, rect.height - effectiveGap)
                    )
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
            .animation(.easeOut(duration: 0.25), value: groups.map { "\($0.id):\($0.ports.count)" })
        }
        .padding(10)
    }
}

// MARK: - 外层进程大块容器

private struct ProcessClusterView: View {
    @Environment(\.colorScheme) private var colorScheme

    let group: NetworkProcessGroup
    let selectedPortID: String?
    let onSelect: (ListeningPort) -> Void
    let onOpen: (ListeningPort) -> Void
    let onCopy: (ListeningPort) -> Void
    let onReveal: (ListeningPort) -> Void
    let onKill: (ListeningPort) -> Void

    private var accent: Color {
        NetworkPortsCard.categoryColor(group.dominantCategory)
    }

    var body: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        VStack(alignment: .leading, spacing: 6) {
            clusterHeader

            GeometryReader { inner in
                let gap: CGFloat = 6
                let cols = NetworkPortGroups.gridColumns(
                    forItemCount: group.ports.count,
                    in: inner.size,
                    gap: gap,
                    minTileWidth: 84
                )
                let rows = max(1, Int(ceil(Double(group.ports.count) / Double(cols))))
                let availableH = inner.size.height - gap * CGFloat(rows - 1)
                let idealTileH = availableH / CGFloat(rows)
                let minTileH: CGFloat = 50
                let needsScroll = idealTileH < minTileH
                let tileH = max(minTileH, idealTileH)
                let gridColumns = Array(repeating: GridItem(.flexible(), spacing: gap), count: cols)

                if needsScroll {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: gap) {
                            portTiles(tileHeight: tileH)
                        }
                    }
                } else {
                    LazyVGrid(columns: gridColumns, spacing: gap) {
                        portTiles(tileHeight: tileH)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape
                .fill(isLight ? Color.white.opacity(0.72) : Color.white.opacity(0.03))
                .overlay {
                    LinearGradient(
                        colors: [
                            accent.opacity(isLight ? 0.11 : 0.14),
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
        .frame(height: 18)
    }

    @ViewBuilder
    private func portTiles(tileHeight: CGFloat) -> some View {
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
}

// MARK: - 内层等大端口瓷砖

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
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        GeometryReader { proxy in
            let compact = proxy.size.height < 64 || proxy.size.width < 108

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                // 顶行：分类标签 + 活跃连接 / 对外暴露提示
                HStack(spacing: 4) {
                    Text(verbatim: NetworkPortsCard.categoryTag(item.category))
                        .font(.system(size: compact ? 8 : 8.5, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(
                            categoryColor.opacity(isLight ? 0.16 : 0.20),
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
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(PanelPalette.treemapTextSecondary)
                    }
                }

                Spacer(minLength: 0)

                // 核心端口号：大号等宽字
                Text(verbatim: ":\(item.port)")
                    .font(.system(size: compact ? 14 : 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(PanelPalette.treemapTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                // 底行：监听地址（多 PID 时附带 PID）
                HStack(spacing: 4) {
                    Text(verbatim: item.bindAddress)
                        .font(.system(size: compact ? 8.5 : 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.treemapTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if showPID && !compact {
                        Spacer(minLength: 2)
                        Text(verbatim: "#\(item.pid)")
                            .font(.system(size: 8.5, weight: .regular).monospacedDigit())
                            .foregroundStyle(PanelPalette.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 5 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
