import AppKit
import SwiftUI

@main
struct PeekApp: App {
    @Environment(\.openWindow) private var openWindow
    private var languageManager: LanguageManager = .shared
    private var appearanceManager: AppearanceManager = .shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(\.locale, languageManager.locale)
                .preferredColorScheme(appearanceManager.colorScheme)
        } label: {
            MenuBarLabel()
                .environment(\.locale, languageManager.locale)
                .task {
                    appearanceManager.applyToApplication()
                    StatusItemMenu.shared.install { destination in
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(value: destination)
                    }
                }
        }
        .menuBarExtraStyle(.window)

        // 独立窗口。目前内容是占位,各功能做好后替换(见 `DestinationWindow`)。
        WindowGroup("Peek", for: PanelDestination.self) { $destination in
            DestinationWindow(destination: destination ?? .home)
                .environment(\.locale, languageManager.locale)
                .preferredColorScheme(appearanceManager.colorScheme)
        } defaultValue: {
            .home
        }
        .windowResizability(.contentMinSize)
    }
}

/// 菜单栏上的 Bento 图标和健康分,如 "⊞ 81"。
private struct MenuBarLabel: View {
    var monitor: SystemMonitor = .shared

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarBentoIcon.templateImage)
            Text(verbatim: "\(monitor.health.value)")
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Peek health \(monitor.health.value)"))
    }
}

/// 与 `AppIcon.icns` 一致的非对称 2×2 Bento 网格菜单栏模板图标（自动适配浅色/深色系统菜单栏）。
private enum MenuBarBentoIcon {
    static let templateImage: NSImage = {
        let size = NSSize(width: 15, height: 15)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            let radius: CGFloat = 1.6
            let gap: CGFloat = 1.6
            let marginX: CGFloat = 1.0
            let marginY: CGFloat = 1.0
            let totalW = size.width - marginX * 2
            let totalH = size.height - marginY * 2
            let rowH = (totalH - gap) / 2
            let wideW = (totalW - gap) * 0.62
            let narrowW = totalW - gap - wideW

            let rects = [
                // 左上（宽）
                NSRect(x: marginX, y: marginY, width: wideW, height: rowH),
                // 右上（窄）
                NSRect(x: marginX + wideW + gap, y: marginY, width: narrowW, height: rowH),
                // 左下（窄）
                NSRect(x: marginX, y: marginY + rowH + gap, width: narrowW, height: rowH),
                // 右下（宽）
                NSRect(x: marginX + narrowW + gap, y: marginY + rowH + gap, width: wideW, height: rowH),
            ]
            for rect in rects {
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
