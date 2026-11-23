import AppKit
import SwiftUI

/// `MenuBarExtra` 不支持右键菜单,这里监听菜单栏图标上的右键,弹出"打开 Peek / 设置 / 退出"。
///
/// 靠窗口类名识别菜单栏图标的窗口(`NSStatusBarWindow`),这是系统私有类名,
/// 如果以后系统改名,右键菜单会失效但左键面板不受影响。
@MainActor
final class StatusItemMenu {
    static let shared = StatusItemMenu()

    private var monitor: Any?
    private var open: ((PanelDestination) -> Void)?

    /// 只需在应用启动后调用一次。`open` 负责打开对应的独立窗口。
    func install(open: @escaping (PanelDestination) -> Void) {
        self.open = open
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let window = event.window,
                  String(describing: type(of: window)).contains("StatusBarWindow"),
                  let view = window.contentView
            else { return event }
            MainActor.assumeIsolated { self?.showMenu(event: event, view: view) }
            return nil
        }
    }

    private func showMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "Open Peek"), #selector(openHome)))
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Peek"), #selector(quit), key: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openHome() { open?(.home) }
    @objc private func openSettings() { open?(.settings) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
