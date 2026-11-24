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

/// 菜单栏上的 Bento 图标和用户选择的实时指标。
///
/// SwiftUI 的 `MenuBarExtra` 只会把 label 里第一个 `Image` 和第一个 `Text` 映射到 `NSStatusBarButton`，
/// 放两个 `Image` 会丢掉第二个，所以把图标与固定宽度的指标合并绘制为单张模板 `NSImage`。
private struct MenuBarLabel: View {
    var monitor: SystemMonitor = .shared
    var metricManager: MenuBarMetricManager = .shared

    var body: some View {
        let metric = metricManager.metric
        let value = metric.formattedText(for: monitor.snapshot)
        Image(nsImage: MenuBarStatusImage.render(metric: metric, snapshot: monitor.snapshot))
            .accessibilityLabel(value.map { Text("Peek \($0)") } ?? Text("Peek"))
    }
}

/// 菜单栏状态项的单张固定宽度模板图（左：15×15 Bento 图标，右：固定宽度指标文字）：
/// - 仅图标：15×15 Bento 图标。
/// - CPU / 内存 / 温度：按 2 位数（`99%` / `99°C`）定宽并左对齐贴紧图标；偶发 3 位数自动微缩字号塞入同宽，零抖动。
/// - 网络：双行紧凑堆叠（`↑` 在上、`↓` 在下），宽度缩减一半以上且同样固定宽度零抖动。
@MainActor
private enum MenuBarStatusImage {
    private nonisolated static let height: CGFloat = 18
    private nonisolated static let iconSize: CGFloat = 15
    private nonisolated static let iconGap: CGFloat = 4
    private nonisolated static let baseFontSize: CGFloat = 12

    private nonisolated static func singleLineAttributes(fontSize: CGFloat = baseFontSize) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
    }

    private nonisolated static func stackedAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
    }

    private static let percentWidth: CGFloat = ceil(("99%" as NSString).size(withAttributes: singleLineAttributes()).width)
    private static let tempWidth: CGFloat = ceil(("99°C" as NSString).size(withAttributes: singleLineAttributes()).width)
    private static let arrowWidth: CGFloat = ceil(("↑" as NSString).size(withAttributes: stackedAttributes()).width)
    private static let rateValueWidth: CGFloat = ceil(("999K" as NSString).size(withAttributes: stackedAttributes()).width)
    private static let networkWidth: CGFloat = arrowWidth + 1 + rateValueWidth

    static func render(metric: MenuBarMetric, snapshot: SystemSnapshot) -> NSImage {
        switch metric {
        case .none:
            return MenuBarBentoIcon.templateImage
        case .cpu:
            return singleLine(PanelFormat.percent(snapshot.cpu.total), textWidth: percentWidth)
        case .memory:
            return singleLine(PanelFormat.percent(snapshot.memory.usedFraction), textWidth: percentWidth)
        case .temperature:
            return singleLine(PanelFormat.temperature(snapshot.thermal.temperatureCelsius), textWidth: tempWidth)
        case .network:
            let rates = MenuBarMetric.networkRates(for: snapshot.network)
            return stackedNetwork(up: rates.up, down: rates.down)
        }
    }

    private static func singleLine(_ text: String, textWidth: CGFloat) -> NSImage {
        let totalWidth = iconSize + iconGap + textWidth
        let textOriginX = iconSize + iconGap
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { _ in
            MenuBarBentoIcon.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))

            let ns = text as NSString
            var fontSize = baseFontSize
            var attrs = singleLineAttributes(fontSize: fontSize)
            var size = ns.size(withAttributes: attrs)
            // 偶发 3 位数（如 100% / 100°C）超出 2 位数框时，微缩字号适配同一固定宽度。
            if size.width > textWidth {
                fontSize = max(8.5, floor(baseFontSize * (textWidth / size.width) * 2) / 2)
                attrs = singleLineAttributes(fontSize: fontSize)
                size = ns.size(withAttributes: attrs)
                while size.width > textWidth, fontSize > 8.5 {
                    fontSize -= 0.5
                    attrs = singleLineAttributes(fontSize: fontSize)
                    size = ns.size(withAttributes: attrs)
                }
            }
            let y = (height - size.height) / 2
            ns.draw(at: NSPoint(x: textOriginX, y: y), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stackedNetwork(up: String, down: String) -> NSImage {
        let textWidth = networkWidth
        let totalWidth = iconSize + iconGap + textWidth
        let textOriginX = iconSize + iconGap
        let arrowW = arrowWidth
        let rowHeight = height / 2
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { _ in
            MenuBarBentoIcon.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))

            let attrs = stackedAttributes()
            let upArrow = "↑" as NSString
            let downArrow = "↓" as NSString
            let upText = up as NSString
            let downText = down as NSString

            let textHeight = upText.size(withAttributes: attrs).height
            let topY = (rowHeight - textHeight) / 2
            let bottomY = rowHeight + (rowHeight - textHeight) / 2

            upArrow.draw(at: NSPoint(x: textOriginX, y: topY), withAttributes: attrs)
            let upWidth = upText.size(withAttributes: attrs).width
            upText.draw(
                at: NSPoint(x: textOriginX + max(arrowW + 1, textWidth - upWidth), y: topY),
                withAttributes: attrs)

            downArrow.draw(at: NSPoint(x: textOriginX, y: bottomY), withAttributes: attrs)
            let downWidth = downText.size(withAttributes: attrs).width
            downText.draw(
                at: NSPoint(x: textOriginX + max(arrowW + 1, textWidth - downWidth), y: bottomY),
                withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// 与 `AppIcon.icns` 一致的非对称 2×2 Bento 网格菜单栏模板图标（自动适配浅色/深色系统菜单栏）。
private enum MenuBarBentoIcon {
    @MainActor
    static let templateImage: NSImage = {
        let size = NSSize(width: 15, height: 15)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(in: NSRect(origin: .zero, size: size))
            return true
        }
        image.isTemplate = true
        return image
    }()

    nonisolated static func draw(in bounds: NSRect) {
        NSColor.black.setFill()
        let radius: CGFloat = 1.6
        let gap: CGFloat = 1.6
        let marginX: CGFloat = 1.0
        let marginY: CGFloat = 1.0
        let originX = bounds.minX + marginX
        let originY = bounds.minY + marginY
        let totalW = bounds.width - marginX * 2
        let totalH = bounds.height - marginY * 2
        let rowH = (totalH - gap) / 2
        let wideW = (totalW - gap) * 0.62
        let narrowW = totalW - gap - wideW

        let rects = [
            // 左上（宽）
            NSRect(x: originX, y: originY, width: wideW, height: rowH),
            // 右上（窄）
            NSRect(x: originX + wideW + gap, y: originY, width: narrowW, height: rowH),
            // 左下（窄）
            NSRect(x: originX, y: originY + rowH + gap, width: narrowW, height: rowH),
            // 右下（宽）
            NSRect(x: originX + narrowW + gap, y: originY + rowH + gap, width: wideW, height: rowH),
        ]
        for rect in rects {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}
