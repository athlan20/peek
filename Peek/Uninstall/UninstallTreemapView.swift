import AppKit
import SwiftUI

/// 卸载窗口的方块视图:每个 App 一个方块,面积就是它占的空间。
/// 这里只把 `[InstalledApp]` 转成方块数据、接上"最后使用"的颜色和菜单,画方块的是公共组件
/// `TreemapView`。规格见 `docs/uninstall-treemap.md`。
struct UninstallTreemapView: View {
    /// 已经过搜索筛选的 App。
    let apps: [InstalledApp]
    /// 选中的 App id,就是 `.app` 的路径。
    @Binding var selectedID: String?
    /// 双击可以卸载的方块:进预览残留页。
    let onPreview: (InstalledApp) -> Void
    /// 双击"其他"方块:切到列表看全部。
    let onShowAll: () -> Void
    /// 算颜色用的"现在",测试可以换成固定的时间。
    var now = Date.now

    var body: some View {
        TreemapView(
            entries: UninstallTreemap.entries(apps: apps, now: now).map { entry in
                var entry = entry
                entry.icon = UninstallTreemapIcons.icon(forFile: entry.id)
                return entry
            },
            isLoading: false,
            emptyText: Text("Nothing to show."),
            selectedID: selectedID,
            otherTitle: L10n.text("Other"),
            otherSubtitle: { L10n.text("\($0) items") },
            onTap: { entry in
                // 单击只选中,不做事;正在运行、系统 App 也能选中看看到底是哪个。
                selectedID = entry.id
            },
            onDoubleTap: { entry in
                guard let app = app(for: entry), app.blocked == nil else { return }
                onPreview(app)
            },
            onTapOther: { _ in
                // "其他"方块不能选中。
            },
            onDoubleTapOther: { _ in onShowAll() },
            hasMenu: { entry in app(for: entry) != nil },
            menu: { entry in
                if let app = app(for: entry) {
                    UninstallAppMenu(app: app, onPreview: onPreview)
                }
            },
            // 不按占比合并,只留 80 块上限,免得几十 MB 的小 App 全进"其他"。
            minFraction: 0,
            bentoStyle: true)
    }

    private func app(for entry: TreemapEntry) -> InstalledApp? {
        apps.first { $0.id == entry.id }
    }
}

/// 方块和后续可能复用的右键菜单。不能卸载的只留"在访达中显示"。
struct UninstallAppMenu: View {
    let app: InstalledApp
    let onPreview: (InstalledApp) -> Void

    var body: some View {
        if app.blocked == nil {
            Button("Uninstall…") { onPreview(app) }
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
    }
}

// MARK: - 方块数据

/// `InstalledApp` → 方块。纯函数,不依赖视图(图标由视图补),方便单元测试。
enum UninstallTreemap {
    /// 还没量完大小的 App 不画;量完是 0 的也不画。
    static func entries(apps: [InstalledApp], now: Date) -> [TreemapEntry] {
        apps.compactMap { entry(for: $0, now: now) }
    }

    static func entry(for app: InstalledApp, now: Date) -> TreemapEntry? {
        guard let bytes = app.bytes, bytes > 0 else { return nil }
        let sizeText = TreemapText.size(bytes)
        let state = state(for: app.blocked)
        return TreemapEntry(
            id: app.id,
            title: app.name,
            // 副标题留给方块上的字,不放 Bundle ID:方块太小放不下,悬停提示里都有。
            subtitle: nil,
            size: bytes,
            color: UninstallTreemapColors.color(lastUsed: app.lastUsed, now: now),
            dimLevel: state.dimLevel,
            badge: state.badge,
            tooltip: tooltip(for: app, sizeText: sizeText),
            accessibilityLabel: "\(app.name), \(sizeText)")
    }

    /// 不能卸载的显示方式:正在运行只是轻微变暗,其他原因明显变暗并带锁。
    enum State: Equatable, Sendable {
        case available, running, locked

        var dimLevel: TreemapDim {
            switch self {
            case .available: .none
            case .running: .light
            case .locked: .strong
            }
        }

        var badge: TreemapBadge? {
            switch self {
            case .available: nil
            case .running: .running
            case .locked: .lock
            }
        }
    }

    static func state(for reason: UninstallBlockReason?) -> State {
        switch reason {
        case nil: .available
        case .running: .running
        default: .locked
        }
    }

    /// 悬停提示:方块上放不下的都写在这里,一行一条。
    static func tooltip(for app: InstalledApp, sizeText: String) -> String {
        let locale = L10n.currentLocale()
        var lines = [app.name, sizeText, L10n.text("Bundle ID \(app.bundleID)", locale: locale)]
        if app.isAppStore { lines.append(L10n.text("From the App Store", locale: locale)) }
        if let lastUsed = app.lastUsed {
            let relative = lastUsed.formatted(
                Date.RelativeFormatStyle(presentation: .named).locale(locale)
            )
            lines.append(L10n.text("Last used \(relative)", locale: locale))
        } else {
            lines.append(L10n.text("No record", locale: locale))
        }
        if let reason = app.blocked { lines.append(reason.explanation) }
        lines.append(L10n.text("Only the app itself. Leftover files are shown before uninstalling.", locale: locale))
        return lines.joined(separator: "\n")
    }
}

extension UninstallBlockReason {
    /// 悬停提示里的原因,和列表里显示的一致。
    var explanation: String {
        switch self {
        case .systemApp: L10n.text("System app")
        case .peekItself: L10n.text("Peek can’t uninstall itself")
        case .appleApp: L10n.text("Apple system app")
        case .vendorManaged: L10n.text("Use the vendor’s own uninstaller")
        case .running: L10n.text("Running — quit it first")
        }
    }
}

// MARK: - 颜色

/// 最后使用的档位,从最近用过到很久没用,逐级偏暖。
enum UninstallUsageBand: String, CaseIterable, Sendable {
    case week, month, quarter, year, older, unknown

    /// 图例和悬停提示里的文字。
    var title: LocalizedStringKey {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .quarter: "Last 90 days"
        case .year: "Last year"
        case .older: "Over a year"
        case .unknown: "No record"
        }
    }
}

/// 方块颜色。都是压暗过的中等色,深浅色模式下都配白字;从冷到暖逐档过渡。
enum UninstallTreemapColors {
    private static let day: TimeInterval = 24 * 60 * 60

    static func band(lastUsed: Date?, now: Date) -> UninstallUsageBand {
        guard let lastUsed else { return .unknown }
        let age = now.timeIntervalSince(lastUsed)
        switch age {
        case ...(7 * day): return .week
        case ...(30 * day): return .month
        case ...(90 * day): return .quarter
        case ...(365 * day): return .year
        default: return .older
        }
    }

    static func color(lastUsed: Date?, now: Date) -> Color {
        color(band(lastUsed: lastUsed, now: now))
    }

    static func color(_ band: UninstallUsageBand) -> Color {
        rgb(hex(band))
    }

    /// 档位对应的色值,单元测试也看这个。
    static func hex(_ band: UninstallUsageBand) -> UInt32 {
        switch band {
        case .week: 0x3E5C8A    // 蓝灰
        case .month: 0x48685F   // 青灰
        case .quarter: 0x6B6A3E // 橄榄
        case .year: 0x7E5F36    // 赭石
        case .older: 0x7A4A32   // 橙褐
        case .unknown: 0x4A4F5C // 中灰
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - 图标

/// 方块图标要读磁盘,缓存起来,免得后台逐个补大小时每次重画都去读。
@MainActor
private enum UninstallTreemapIcons {
    static var cache: [String: NSImage] = [:]

    static func icon(forFile path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}