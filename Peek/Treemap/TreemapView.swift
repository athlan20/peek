import AppKit
import SwiftUI

/// 公共方块视图:把一组带大小的条目画成 treemap,响应点击、悬停和右键。
/// 布局、"其他"合并、颜色、提示文字和菜单都由调用方给,见 `docs/analyze-treemap.md` 的"公共组件"。
struct TreemapView<MenuContent: View>: View {
    let entries: [TreemapEntry]
    /// 还没有可画的方块、又正在加载时转圈。
    let isLoading: Bool
    /// 没有可画的方块时显示的文字。
    let emptyText: Text
    /// 选中的方块 id;不要选中的调用方传 nil。
    let selectedID: String?
    let otherTitle: String
    /// "其他"方块的副标题,参数是被合并的项数。
    let otherSubtitle: (Int) -> String
    let onTap: (TreemapEntry) -> Void
    let onDoubleTap: (TreemapEntry) -> Void
    /// 单击 / 双击"其他"方块,参数是被合并的条目。
    let onTapOther: ([TreemapEntry]) -> Void
    let onDoubleTapOther: ([TreemapEntry]) -> Void
    /// 这一项有没有右键菜单。返回 false 时不挂菜单，免得弹出空菜单。
    let hasMenu: (TreemapEntry) -> Bool
    @ViewBuilder let menu: (TreemapEntry) -> MenuContent
    /// 占比不到这个值就并进"其他"。默认和 `TreemapLayout.minFraction` 一样;传 0 只留数量上限。
    var minFraction = TreemapLayout.minFraction
    /// 开启暗色 Bento 风格方块（圆角、微光描边、更舒适的缝隙）。
    var bentoStyle = false

    var body: some View {
        let tiles = TreemapTiles.make(
            entries: entries, otherTitle: otherTitle, otherSubtitle: otherSubtitle, minFraction: minFraction)
        VStack(spacing: 0) {
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tiles.isEmpty {
                emptyText
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let rects = TreemapLayout.squarify(
                        tiles.map { Double($0.size) },
                        in: CGRect(origin: .zero, size: proxy.size))
                    let gap: CGFloat = bentoStyle ? 3 : 1
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            // 四条边各自取整,相邻方块共用同一条边,再统一留缝。
                            let raw = rects[index]
                            let rect = CGRect(
                                x: raw.minX.rounded(), y: raw.minY.rounded(),
                                width: raw.maxX.rounded() - raw.minX.rounded(),
                                height: raw.maxY.rounded() - raw.minY.rounded())
                            let effectiveGap = (rect.width > gap * 3 && rect.height > gap * 3) ? gap : 1
                            TreemapTileView(
                                tile: tile,
                                isSelected: tile.entry != nil && tile.entry?.id == selectedID,
                                bentoStyle: bentoStyle
                            )
                            .frame(
                                width: max(0, rect.width - effectiveGap),
                                height: max(0, rect.height - effectiveGap)
                            )
                            .offset(x: rect.minX, y: rect.minY)
                            .onTapGesture(count: 2) { doubleTap(tile) }
                            .onTapGesture { tap(tile) }
                            .contextMenu {
                                if let entry = tile.entry, hasMenu(entry) {
                                    menu(entry)
                                }
                            }
                        }
                    }
                    // 数据每 0.2 秒来一份新快照时,方块平滑地长大、挪位,而不是一跳一跳。
                    .animation(.easeOut(duration: 0.3), value: tiles.map(\.size))
                }
                .padding(.horizontal, bentoStyle ? 10 : 12)
                .padding(.top, bentoStyle ? 10 : 0)
            }
        }
        .padding(.bottom, bentoStyle ? 10 : 8)
    }

    private func tap(_ tile: TreemapTile) {
        guard let entry = tile.entry else {
            onTapOther(tile.members)
            return
        }
        onTap(entry)
    }

    private func doubleTap(_ tile: TreemapTile) {
        guard let entry = tile.entry else {
            onDoubleTapOther(tile.members)
            return
        }
        onDoubleTap(entry)
    }
}

// MARK: - 一个方块

private struct TreemapTileView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tile: TreemapTile
    let isSelected: Bool
    var bentoStyle = false

    @State private var isHovering = false

    var body: some View {
        let isLight = colorScheme == .light
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let layout = TreemapTileLayoutMode.mode(
                width: width, height: height, hasIcon: tile.icon != nil)
            let cornerRadius: CGFloat = bentoStyle ? min(6, min(width, height) * 0.22) : 0
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let isOtherTile = tile.entry == nil

            ZStack {
                if bentoStyle {
                    shape.fill(isOtherTile ? PanelPalette.treemapOtherFill : tile.color)
                    // 顶部微弱玻璃高光渐变，呼应主面板 Bento 卡片质感。
                    shape.fill(
                        LinearGradient(
                            colors: isLight
                                ? [
                                    Color.white.opacity(isHovering ? 0.45 : 0.30),
                                    Color.clear,
                                ]
                                : [
                                    Color.white.opacity(isHovering ? 0.18 : 0.11),
                                    Color.clear,
                                    Color.black.opacity(0.24),
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    Rectangle().fill(tile.color)
                }
                if tile.dimLevel != .none {
                    shape.fill(
                        isLight
                            ? PanelPalette.panelBackground.opacity(tile.dimLevel.overlayOpacity * 0.85)
                            : Color.black.opacity(tile.dimLevel.overlayOpacity)
                    )
                }
                if isHovering {
                    shape.fill(isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.08))
                }
                if let icon = tile.icon {
                    tileContent(layout: layout, icon: icon, width: width, height: height)
                } else if layout == .textOnly {
                    labels(width: width, height: height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(6)
                }
                if bentoStyle {
                    shape.strokeBorder(
                        isSelected
                            ? PanelPalette.treemapSelectionBorder
                            : (isLight
                                ? Color(nsColor: PanelPalette.nsColor(hex: 0x0F172A, alpha: isHovering ? 0.28 : 0.12))
                                : Color.white.opacity(isHovering ? 0.42 : (isOtherTile ? 0.10 : 0.16))),
                        lineWidth: isSelected ? 2.0 : 0.85
                    )
                } else if isSelected {
                    Rectangle().strokeBorder(PanelPalette.treemapSelectionBorder, lineWidth: 2)
                }
            }
            .clipShape(shape)
            .shadow(
                color: bentoStyle && isSelected
                    ? PanelPalette.treemapSelectionBorder.opacity(isLight ? 0.22 : 0.28)
                    : .clear,
                radius: 5
            )
            .overlay(alignment: .topTrailing) {
                if let badge = tile.badge {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            badge.isWarning
                                ? PanelPalette.thermalAccent
                                : (isLight ? PanelPalette.networkAccent : Color.white.opacity(0.9))
                        )
                        .padding(3)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help(Text(verbatim: tile.tooltip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tile.accessibilityLabel))
    }

    /// 有图标时的三种画法:图标 + 文字垂直排开、只文字、只图标。
    @ViewBuilder
    private func tileContent(
        layout: TreemapTileLayoutMode, icon: NSImage, width: CGFloat, height: CGFloat
    ) -> some View {
        switch layout {
        case .none:
            EmptyView()
        case .textOnly:
            labels(width: width, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
        case .iconOnly(let iconSize):
            iconView(icon, size: iconSize)
        case .iconAndText(let iconSize):
            VStack(spacing: TreemapTileLayoutMode.iconTextSpacing) {
                iconView(icon, size: iconSize)
                labels(width: width, height: height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(4)
        }
    }

    private func iconView(_ icon: NSImage, size: CGFloat) -> some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private func labels(width: CGFloat, height: CGFloat) -> some View {
        let isLight = colorScheme == .light
        let large = width >= 180 && height >= 110
        let medium = width >= 90 && height >= 56
        let titleSize: CGFloat = large ? 17 : (medium ? 13 : 11)
        let detailSize: CGFloat = large ? 14 : (medium ? 11 : 10)
        // 第二行是大小;副标题(Agent 名字、"其他"的项数)放第三行,高度不够就不写(悬停提示里有)。
        return VStack(spacing: 2) {
            Text(verbatim: tile.title)
                .font(.system(size: titleSize, weight: bentoStyle ? .semibold : .medium))
                .foregroundStyle(PanelPalette.treemapTextPrimary)
                .shadow(color: bentoStyle && !isLight ? Color.black.opacity(0.35) : .clear, radius: 2, y: 1)
                .lineLimit(1)
                .truncationMode(.middle)
            if height >= 42 {
                Text(verbatim: TreemapText.size(tile.size))
                    .font(.system(size: detailSize, weight: bentoStyle ? .medium : .regular).monospacedDigit())
                    .foregroundStyle(PanelPalette.treemapTextSecondary)
                    .shadow(color: bentoStyle && !isLight ? Color.black.opacity(0.30) : .clear, radius: 1.5, y: 1)
                    .lineLimit(1)
            }
            if let subtitle = tile.subtitle, height >= 60 {
                Text(verbatim: subtitle)
                    .font(.system(size: detailSize - 1))
                    .foregroundStyle(PanelPalette.treemapTextSecondary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .minimumScaleFactor(0.8)
    }
}

private extension TreemapBadge {
    var symbol: String {
        switch self {
        case .check: "checkmark"
        case .halfCheck: "minus"
        case .lock: "lock.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .running: "play.circle.fill"
        }
    }

    var isWarning: Bool { self == .warning }
}