import AppKit
import SwiftUI

/// Analyze 的方块视图:当前文件夹的子项画成 treemap,面积就是占用大小,规格见 `docs/analyze-treemap.md`。
/// 画方块的部分是公共组件 `TreemapView`,这里只把 `AnalyzeItem` 转成方块数据、接上磁盘分析的颜色和菜单。
struct AnalyzeTreemapView: View {
    let items: [AnalyzeItem]
    let isScanning: Bool
    /// 没有可画的子项时显示的文字。
    var emptyText = Text("Nothing to show.")
    @Binding var selection: URL?
    /// 双击文件夹方块。
    let onEnter: (AnalyzeItem) -> Void
    /// 双击"其他"方块:切到列表看全部。
    let onShowAll: () -> Void
    /// 右键菜单：在访达中显示、删除（移到废纸篓，先确认）。
    let onReveal: (AnalyzeItem) -> Void
    let onDelete: (AnalyzeItem) -> Void

    private let home = AnalyzeModel.homeURL

    var body: some View {
        TreemapView(
            entries: entries,
            isLoading: isScanning,
            emptyText: emptyText,
            selectedID: selection?.absoluteString,
            otherTitle: L10n.text("Other"),
            otherSubtitle: { L10n.text("\($0) items") },
            onTap: { entry in
                // 单击只选中,不做事。
                selection = URL(string: entry.id)
            },
            onDoubleTap: { entry in
                if let item = item(for: entry) { open(item) }
            },
            onTapOther: { _ in
                // "其他"方块不能选中,单击不做动作。
            },
            onDoubleTapOther: { _ in onShowAll() },
            hasMenu: { entry in
                guard let item = item(for: entry) else { return false }
                return item.url.isFileURL || !isScanning
            },
            menu: { entry in
                if let item = item(for: entry) {
                    AnalyzeItemMenu(item: item, onReveal: onReveal, onDelete: onDelete)
                }
            },
            bentoStyle: true)
    }

    // MARK: - 方块数据

    private var entries: [TreemapEntry] {
        items.map { item in
            let agent = AnalyzeClassifier.agent(for: item.url, home: home)
            let category = AnalyzeClassifier.category(for: item.url, isDirectory: item.isDirectory, home: home)
            let sizeText = TreemapText.size(item.size)
            var lines = [item.name]
            // Agent 页第一层的块本身就叫 Agent 名字，不再重复写一遍。
            let subtitle = agent?.name == item.name ? nil : agent?.name
            if let subtitle { lines.append(subtitle) }
            lines.append(sizeText)
            if item.url.isFileURL { lines.append(item.url.path) }
            return TreemapEntry(
                // 用完整 URL:Agent 页第一层的虚拟 URL 没有 path,用 path 会全部撞成同一个 id。
                id: item.url.absoluteString,
                title: item.name,
                subtitle: subtitle,
                size: item.size,
                color: AnalyzeTreemapColors.color(for: category, agent: agent),
                tooltip: lines.joined(separator: "\n"),
                accessibilityLabel: "\(item.name), \(sizeText)")
        }
    }

    private func item(for entry: TreemapEntry) -> AnalyzeItem? {
        items.first { $0.url.absoluteString == entry.id }
    }

    private func open(_ item: AnalyzeItem) {
        if item.isDirectory, !item.isInaccessible {
            onEnter(item)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }
}

/// 方块和列表行共用的右键菜单。
struct AnalyzeItemMenu: View {
    let item: AnalyzeItem
    let onReveal: (AnalyzeItem) -> Void
    let onDelete: (AnalyzeItem) -> Void

    var body: some View {
        Button("Reveal in Finder") { onReveal(item) }
        Divider()
        Button("Delete…", role: .destructive) { onDelete(item) }
    }
}

// MARK: - 颜色

/// 方块颜色:深色模式下为压暗中等色配白字；浅色模式下为柔彩浅底配深字（方案 A）。
enum AnalyzeTreemapColors {
    private static let darkBase: UInt32 = 0x161E2B
    private static let lightBase: UInt32 = 0xFFFFFF

    private static let agentColor = PanelPalette.dynamicHex(dark: 0x5E4B8B, light: 0xE3D9F7)
    private static let appsColor = PanelPalette.dynamicHex(dark: 0x28558A, light: 0xD2E5FA)
    private static let developerColor = PanelPalette.dynamicHex(dark: 0x1E6B52, light: 0xC9F0DF)
    private static let mediaColor = PanelPalette.dynamicHex(dark: 0x883F5E, light: 0xF5D2E1)
    private static let documentsColor = PanelPalette.dynamicHex(dark: 0x8A5D24, light: 0xF6E1BE)
    private static let systemColor = PanelPalette.dynamicHex(dark: 0x364458, light: 0xDDE5F0)
    private static let otherColor = PanelPalette.dynamicHex(dark: 0x263142, light: 0xE6ECF4)

    static func color(for category: AnalyzeCategory, agent: AnalyzeAgent?) -> Color {
        if let brand = agent?.brandColor {
            return PanelPalette.dynamicHex(
                dark: mix(brand, darkBase, 0.65),
                light: mix(brand, lightBase, 0.22)
            )
        }
        switch category {
        case .agent:     return agentColor
        case .apps:      return appsColor
        case .developer: return developerColor
        case .media:     return mediaColor
        case .documents: return documentsColor
        case .system:    return systemColor
        case .other:     return otherColor
        }
    }

    /// `a` 占 `t`,`b` 占 `1 - t`。
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) }
        var result: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let mixed = channel(a, shift) * t + channel(b, shift) * (1 - t)
            result |= UInt32(max(0, min(255, mixed.rounded()))) << shift
        }
        return result
    }
}