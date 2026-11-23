import AppKit
import Foundation
import Observation
import SwiftUI

/// 应用界面外观模式选项。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    /// 跟随 macOS 系统外观（默认）。
    case system
    /// 浅色模式。
    case light
    /// 深色模式。
    case dark

    var id: String { rawValue }

    /// 供 SwiftUI `.preferredColorScheme(...)` 使用；`system` 返回 `nil` 交由系统决定。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// 供 `NSApp.appearance` 同步窗口标题栏、系统弹窗及动态 `NSColor` 解析。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// 本地化显示名称。
    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "settings.appearance.system"
        case .light: "settings.appearance.light"
        case .dark: "settings.appearance.dark"
        }
    }
}

/// 全局外观状态：驱动 SwiftUI 视图与 AppKit 窗口实时切换浅色/深色/跟随系统。
@MainActor
@Observable
final class AppearanceManager {
    static let shared = AppearanceManager()

    private let store: SettingsStore

    private(set) var appearance: AppAppearance

    var colorScheme: ColorScheme? { appearance.colorScheme }

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.appearance = store.appAppearance
    }

    func applyToApplication() {
        NSApp?.appearance = appearance.nsAppearance
    }

    func setAppearance(_ newAppearance: AppAppearance) {
        guard appearance != newAppearance else { return }
        store.appAppearance = newAppearance
        appearance = store.appAppearance
        applyToApplication()
    }
}
