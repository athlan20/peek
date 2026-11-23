import SwiftUI

/// 面板上的按钮能打开的窗口。各功能做好后,把 `DestinationWindow` 里对应的占位换成真正的界面。
enum PanelDestination: String, Codable, Hashable, CaseIterable {
    case home
    case settings
    case analyze
    case uninstall

    var title: LocalizedStringKey {
        switch self {
        case .home: "Peek"
        case .settings: "Settings"
        case .analyze: "Analyze"
        case .uninstall: "Uninstall"
        }
    }
}

/// 独立窗口的内容。
struct DestinationWindow: View {
    let destination: PanelDestination

    var body: some View {
        content
            .navigationTitle(Text(destination.title))
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .uninstall:
            UninstallView()
        case .analyze:
            AnalyzeView()
        case .settings:
            SettingsView()
        default:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Text(destination.title)
                .font(.title2)
            Text("Coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}

/// 打开独立窗口。Peek 没有 Dock 图标,窗口出来前要先把自己激活到前台。
@MainActor
struct DestinationOpener {
    let openWindow: OpenWindowAction

    func callAsFunction(_ destination: PanelDestination) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(value: destination)
    }
}
