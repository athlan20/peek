import Foundation
import Observation
import SwiftUI

/// 菜单栏图标右侧显示的实时指标选项。
enum MenuBarMetric: String, CaseIterable, Identifiable, Sendable {
    /// CPU 总占用百分比，如 "23%"。
    case cpu
    /// 内存占用百分比，如 "68%"。
    case memory
    /// 网络实时上下行流量，如 "↓1.2M ↑240K"。
    case network
    /// CPU / 整机温度，如 "43°C"。
    case temperature
    /// 不显示数字，仅显示图标。
    case none

    var id: String { rawValue }

    /// 本地化显示名称。
    var titleKey: LocalizedStringKey {
        switch self {
        case .cpu: "settings.menubar.cpu"
        case .memory: "settings.menubar.memory"
        case .network: "settings.menubar.network"
        case .temperature: "settings.menubar.temperature"
        case .none: "settings.menubar.none"
        }
    }

    /// 菜单栏右侧显示的紧凑文本；`.none` 返回 nil（仅显示图标）。
    func formattedText(for snapshot: SystemSnapshot) -> String? {
        switch self {
        case .cpu:
            return PanelFormat.percent(snapshot.cpu.total)
        case .memory:
            return PanelFormat.percent(snapshot.memory.usedFraction)
        case .network:
            let rates = Self.networkRates(for: snapshot.network)
            return "↑\(rates.up) ↓\(rates.down)"
        case .temperature:
            return PanelFormat.temperature(snapshot.thermal.temperatureCelsius)
        case .none:
            return nil
        }
    }

    /// 网络上下行紧凑文案，供菜单栏双行堆叠渲染使用（每行最多 4 个字符，如 "240K"、"1.2M"、"12M"）。
    static func networkRates(for network: NetworkStats) -> (up: String, down: String) {
        (compactRate(network.upBytesPerSecond), compactRate(network.downBytesPerSecond))
    }

    /// 紧凑网速（如 "0K"、"240K"、"1.2M"、"12M"、"1.5G"），控制在 4 字符以内方便固定字宽。
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let bps = max(0, bytesPerSecond)
        if bps >= 1_000_000_000 {
            return formatCompactValue(bps / 1_000_000_000, unit: "G")
        }
        if bps >= 1_000_000 {
            return formatCompactValue(bps / 1_000_000, unit: "M")
        }
        let kb = Int((bps / 1_000).rounded())
        if kb >= 1_000 {
            return "1M"
        }
        return "\(kb)K"
    }

    private static func formatCompactValue(_ value: Double, unit: String) -> String {
        if value >= 10 {
            return "\(Int(value.rounded()))\(unit)"
        }
        let rounded = (value * 10).rounded() / 10
        if rounded >= 10 {
            return "\(Int(rounded))\(unit)"
        }
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))\(unit)"
        }
        return String(format: "%.1f%@", rounded, unit)
    }
}

/// 菜单栏渲染所需的轻量显示值。只包含格式化后的文案，用于按值去重，避免未变化时触发 SwiftUI / NSImage 重绘。
enum MenuBarDisplayValue: Hashable, Sendable {
    case none
    case singleLine(metric: MenuBarMetric, text: String)
    case network(up: String, down: String)

    var accessibilityValue: String? {
        switch self {
        case .none:
            return nil
        case .singleLine(_, let text):
            return text
        case .network(let up, let down):
            return "↑\(up) ↓\(down)"
        }
    }

    static func make(metric: MenuBarMetric, snapshot: SystemSnapshot) -> MenuBarDisplayValue {
        switch metric {
        case .none:
            return .none
        case .cpu:
            return .singleLine(metric: .cpu, text: PanelFormat.percent(snapshot.cpu.total))
        case .memory:
            return .singleLine(metric: .memory, text: PanelFormat.percent(snapshot.memory.usedFraction))
        case .temperature:
            return .singleLine(metric: .temperature, text: PanelFormat.temperature(snapshot.thermal.temperatureCelsius))
        case .network:
            let rates = MenuBarMetric.networkRates(for: snapshot.network)
            return .network(up: rates.up, down: rates.down)
        }
    }
}

/// 全局菜单栏显示指标状态：驱动菜单栏标签与设置窗口实时同步。
@MainActor
@Observable
final class MenuBarMetricManager {
    static let shared = MenuBarMetricManager()

    private let store: SettingsStore

    private(set) var metric: MenuBarMetric

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.metric = store.menuBarMetric
    }

    func setMetric(_ newMetric: MenuBarMetric) {
        guard metric != newMetric else { return }
        store.menuBarMetric = newMetric
        metric = store.menuBarMetric
        SystemMonitor.shared.restartTimer()
    }
}
