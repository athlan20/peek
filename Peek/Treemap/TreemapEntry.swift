import AppKit
import Foundation
import SwiftUI

/// 方块右上角的小图标。不影响文字布局,只有警告用橙色。
enum TreemapBadge: Equatable, Sendable {
    /// 全选。
    case check
    /// 部分选中。
    case halfCheck
    /// 不可用。
    case lock
    /// 要注意。
    case warning
    /// 正在运行,暂时不能操作。
    case running
}

/// 方块压暗的强度。黑色蒙层,强度不同:`.light` 只是轻微变暗(如 App 正在运行),
/// `.strong` 明显变暗(如不可用)。
enum TreemapDim: Equatable, Sendable {
    case none
    case light
    case strong

    /// 黑色蒙层的不透明度。
    var overlayOpacity: Double {
        switch self {
        case .none: 0
        case .light: 0.18
        case .strong: 0.45
        }
    }
}

/// 方块视图的一项。数据由调用方给:标题、颜色、提示文字都是调用方拼好的,组件只管画和响应点击。
///
/// `NSImage` 不是 Sendable,方块只在主线程画,所以整个结构体用 `@unchecked`。
struct TreemapEntry: Identifiable, Equatable, @unchecked Sendable {
    /// 唯一标识,选中和回调用。要和条目一一对应。
    let id: String
    let title: String
    let subtitle: String?
    let size: UInt64
    /// 底色。
    let color: Color
    /// 变暗,用于不可用、未勾选。等价于 `dimLevel = .strong`;要控制强度时用 `dimLevel`。
    var isDimmed = false
    /// 变暗的强度。传了就以这里为准,`isDimmed` 不再起作用。
    var dimLevel: TreemapDim?
    var badge: TreemapBadge?
    /// 方块里的图标。画不画、多大、和文字怎么排见 `TreemapTileLayoutMode`。
    var icon: NSImage?
    /// 悬停提示,调用方拼好(可以多行)。
    var tooltip: String
    var accessibilityLabel: String

    /// 实际用的变暗等级:优先 `dimLevel`,没传就看 `isDimmed`。
    var resolvedDim: TreemapDim {
        dimLevel ?? (isDimmed ? .strong : .none)
    }
}