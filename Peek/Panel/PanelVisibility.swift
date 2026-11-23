import AppKit
import SwiftUI

/// 告诉外面面板窗口当前是否可见。`MenuBarExtra` 的内容视图创建后会一直保留,
/// `onAppear`/`onDisappear` 不可靠,所以直接看窗口的可见状态。
struct PanelVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastVisible: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        @MainActor private func report() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            guard visible != lastVisible else { return }
            lastVisible = visible
            onChange?(visible)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
            }
        }
    }
}
