import SwiftUI

/// 方案二「等大瓷砖矩阵（Port Patch Panel）」：
/// 去掉外层套娃边框，每个监听端口直接是一块等宽等高、居中饱满的圆角微光方块，
/// 按分类优先级顺序自然成片排列，横平竖直、零残片、扫视清晰。
struct NetworkBoardView: View {
    let ports: [ListeningPort]
    let selectedPortID: String?
    let onSelect: (ListeningPort) -> Void
    let onOpen: (ListeningPort) -> Void
    let onCopy: (ListeningPort) -> Void
    let onReveal: (ListeningPort) -> Void
    let onKill: (ListeningPort) -> Void

    private let outerPadding: CGFloat = 12
    private let gridGap: CGFloat = 10
    private let tileHeight: CGFloat = 102

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - outerPadding * 2)
            let cols = NetworkPortGroups.tileColumns(forWidth: contentWidth, gap: gridGap)
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: gridGap), count: cols)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: gridColumns, spacing: gridGap) {
                    ForEach(ports) { item in
                        PortPatchTile(
                            item: item,
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
                .padding(outerPadding)
            }
            .animation(.easeOut(duration: 0.2), value: ports.map(\.id))
        }
    }
}

// MARK: - 单层等大端口瓷砖

private struct PortPatchTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: ListeningPort
    let isSelected: Bool

    @State private var isHovered = false

    private var categoryColor: Color {
        NetworkPortsCard.categoryColor(item.category)
    }

    var body: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        VStack(spacing: 0) {
            // 顶行：分类胶囊 + 活跃连接 / 对外暴露标识
            HStack(spacing: 4) {
                HStack(spacing: 3.5) {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 5, height: 5)
                    Text(verbatim: NetworkPortsCard.categoryTag(item.category))
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(categoryColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    categoryColor.opacity(isLight ? 0.14 : 0.20),
                    in: Capsule()
                )

                Spacer(minLength: 4)

                if item.establishedCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(PanelPalette.segGreen)
                            .frame(width: 5, height: 5)
                        Text(verbatim: "\(item.establishedCount)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PanelPalette.treemapTextSecondary)
                    }
                } else if item.isExposedExternally {
                    Image(systemName: "globe")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(PanelPalette.treemapTextSecondary)
                }
            }

            Spacer(minLength: 4)

            // 中央视觉焦点：大号等宽端口号 + 进程名
            VStack(spacing: 2.5) {
                Text(verbatim: ":\(item.port)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(PanelPalette.treemapTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(verbatim: item.processName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(PanelPalette.treemapTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // 底行：监听地址 + PID
            HStack(spacing: 4) {
                Text(verbatim: item.bindAddress)
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(verbatim: "PID \(item.pid)")
                    .font(.system(size: 9.5, weight: .regular).monospacedDigit())
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(tileBaseFill(isLight: isLight))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: isLight
                                ? [Color.white.opacity(isHovered ? 0.58 : 0.38), Color.clear]
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
                    : categoryColor.opacity(isHovered ? 0.78 : (isLight ? 0.30 : 0.36)),
                lineWidth: isSelected ? 1.8 : (isHovered ? 1.15 : 0.9)
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
            return categoryColor.opacity(isSelected ? 0.22 : (isHovered ? 0.18 : 0.12))
        }
        return categoryColor.opacity(isSelected ? 0.28 : (isHovered ? 0.22 : 0.15))
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
