import AppKit
import Foundation
import SwiftUI

/// 方块视图最终画出来的一个方块:单独成块的一项,或者合并出来的"其他"。
struct TreemapTile: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    /// 单独成块的那一项;"其他"为 nil。
    let entry: TreemapEntry?
    /// "其他"合并进来的项;单独成块时为空。
    let members: [TreemapEntry]

    let title: String
    let subtitle: String?
    let size: UInt64
    let color: Color
    let dimLevel: TreemapDim
    let badge: TreemapBadge?
    let icon: NSImage?
    let tooltip: String
    let accessibilityLabel: String

    var isDimmed: Bool { dimLevel != .none }
}

/// 条目 → 方块。纯计算,不依赖视图,方便单元测试。
enum TreemapTiles {
    /// "其他"方块的底色:压暗的中灰蓝,和磁盘分析原来 `.other` 类一样。
    static let otherColor = Color(
        .sRGB, red: Double(0x3A) / 255, green: Double(0x3F) / 255, blue: Double(0x4A) / 255)

    /// 大小为 0 的条目**不画**(调用方要在别处列出就自己列),其余按大小从大到小排,
    /// 前 `TreemapLayout.individualCount` 个单独成块,剩下的合并成"其他"。
    /// `minFraction` 是并进"其他"的最小占比,默认 0.2%;传 0 就只受方块数量上限约束。
    static func make(
        entries: [TreemapEntry],
        otherTitle: String,
        otherSubtitle: (Int) -> String,
        minFraction: Double = TreemapLayout.minFraction
    ) -> [TreemapTile] {
        let sorted = entries.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let count = TreemapLayout.individualCount(sizes: sorted.map(\.size), minFraction: minFraction)
        var tiles = sorted.prefix(count).map { entry in
            TreemapTile(
                id: entry.id,
                entry: entry,
                members: [],
                title: entry.title,
                subtitle: entry.subtitle,
                size: entry.size,
                color: entry.color,
                dimLevel: entry.resolvedDim,
                badge: entry.badge,
                icon: entry.icon,
                tooltip: entry.tooltip,
                accessibilityLabel: entry.accessibilityLabel)
        }
        let rest = Array(sorted.dropFirst(count))
        if !rest.isEmpty {
            let title = otherTitle
            let subtitle = otherSubtitle(rest.count)
            let size = rest.reduce(UInt64(0)) { $0 &+ $1.size }
            let sizeText = TreemapText.size(size)
            // "其他"方块的提示只有标题、副标题、大小,没有路径。
            let tooltip = [title, subtitle, sizeText].joined(separator: "\n")
            tiles.append(TreemapTile(
                id: "\u{0}other",
                entry: nil,
                members: rest,
                title: title,
                subtitle: subtitle,
                size: size,
                color: otherColor,
                dimLevel: .none,
                badge: nil,
                icon: nil,
                tooltip: tooltip,
                accessibilityLabel: "\(title), \(sizeText)"))
        }
        return tiles
    }
}

/// 方块上的文字。
enum TreemapText {
    /// 大小,和列表视图一样用文件大小格式。
    static func size(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .file))
    }
}