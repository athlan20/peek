import Foundation

/// 面板底部的"距上次清理多久"文案。纯函数，方便测试。
///
/// 从没清理过返回 "Never cleaned"；否则是 "Last cleaned 2h ago"。
/// 小于 1 分钟是 "Last cleaned just now"；分钟用 m、小时用 h、天用 d。
func lastCleanedText(_ date: Date?, now: Date = Date()) -> String {
    guard let date else {
        return String(localized: "Never cleaned")
    }

    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 {
        return String(localized: "Last cleaned just now")
    }

    let duration: String = if seconds < 3600 {
        String(localized: "\(Int(seconds / 60))m")
    } else if seconds < 86_400 {
        String(localized: "\(Int(seconds / 3600))h")
    } else {
        String(localized: "\(Int(seconds / 86_400))d")
    }

    return String(localized: "Last cleaned \(duration) ago")
}