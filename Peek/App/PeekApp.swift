import AppKit
import SwiftUI

@main
struct PeekApp: App {
    @Environment(\.openWindow) private var openWindow
    private var languageManager: LanguageManager = .shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(\.locale, languageManager.locale)
        } label: {
            MenuBarLabel()
                .environment(\.locale, languageManager.locale)
                .task {
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
        } defaultValue: {
            .home
        }
        .windowResizability(.contentMinSize)
    }
}

/// 菜单栏上的图标和健康分,如 "◉ 81"。
private struct MenuBarLabel: View {
    var monitor: SystemMonitor = .shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "record.circle")
            Text(verbatim: "\(monitor.health.value)")
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Peek health \(monitor.health.value)"))
    }
}
