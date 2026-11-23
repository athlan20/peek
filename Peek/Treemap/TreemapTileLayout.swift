import CoreGraphics
import Foundation

/// 一个方块里画什么:只有文字、只有图标,还是图标 + 文字,图标多大。
///
/// 纯函数,不依赖视图,方便单元测试。规则见 `docs/analyze-treemap.md` 的"公共组件"。
/// 没有图标时(磁盘分析不传)只看文字放不放得下,和加图标之前完全一样。
enum TreemapTileLayoutMode: Equatable, Sendable {
    /// 什么都不画,只留色块。
    case none
    /// 只画文字:名称、大小(和副标题)。
    case textOnly
    /// 只画图标,名称放悬停提示里。
    case iconOnly(iconSize: CGFloat)
    /// 图标在上、文字在下,整体居中。
    case iconAndText(iconSize: CGFloat)

    var showsIcon: Bool {
        switch self {
        case .iconOnly, .iconAndText: true
        case .none, .textOnly: false
        }
    }

    var showsText: Bool {
        switch self {
        case .textOnly, .iconAndText: true
        case .none, .iconOnly: false
        }
    }

    /// 图标边长;不画图标时为 nil。
    var iconSize: CGFloat? {
        switch self {
        case .iconOnly(let size), .iconAndText(let size): size
        case .none, .textOnly: nil
        }
    }

    /// 文字放得下的条件,和加图标之前一致。
    static func textFits(width: CGFloat, height: CGFloat) -> Bool {
        width >= 44 && height >= 28
    }

    /// 图标 + 文字要的最小方块,再小就退回只画文字。
    static let iconWithTextWidth: CGFloat = 60
    static let iconWithTextHeight: CGFloat = 84
    /// 大方块用大一点的图标。
    static let largeWidth: CGFloat = 180
    static let largeHeight: CGFloat = 110
    /// 只画图标时方块的最小宽高,以及图标大小。
    static let iconOnlyMinSide: CGFloat = 24
    static let iconOnlySize: CGFloat = 20
    static let iconSize: CGFloat = 32
    static let largeIconSize: CGFloat = 40
    /// 图标和文字之间留的缝。
    static let iconTextSpacing: CGFloat = 4

    static func mode(width: CGFloat, height: CGFloat, hasIcon: Bool) -> TreemapTileLayoutMode {
        let textFits = textFits(width: width, height: height)
        guard hasIcon else {
            // 没有图标:和原来一样,文字放得下就写,放不下就只留色块。
            return textFits ? .textOnly : .none
        }
        if width >= iconWithTextWidth, height >= iconWithTextHeight {
            let large = width >= largeWidth && height >= largeHeight
            return .iconAndText(iconSize: large ? largeIconSize : iconSize)
        }
        if textFits {
            return .textOnly
        }
        if width >= iconOnlyMinSide, height >= iconOnlyMinSide {
            return .iconOnly(iconSize: iconOnlySize)
        }
        return .none
    }
}