import AppKit
import SwiftUI

/// 点击菜单栏图标弹出的主面板：6 张暗色 Bento 监控卡片 + 功能入口 + 底部工具栏。
struct PanelView: View {
    @Environment(\.openWindow) private var openWindow

    /// 系统状态，面板只读它。
    var monitor: SystemMonitor = .shared
    /// 在线更新状态（默认每 24 小时静默检查一次 GitHub Releases）。
    var updater: UpdateManager = .shared

    @State private var refreshRotation: Double = 0

    private var snapshot: SystemSnapshot { monitor.snapshot }
    private var open: DestinationOpener { DestinationOpener(openWindow: openWindow) }

    var body: some View {
        VStack(spacing: 10) {
            // 第一行：CPU + MEM
            HStack(spacing: 10) {
                CPUCard(
                    stats: snapshot.cpu,
                    topProcesses: snapshot.topProcesses
                )
                MemoryCard(
                    stats: snapshot.memory,
                    topMemoryProcesses: snapshot.topMemoryProcesses.isEmpty
                        ? snapshot.topProcesses
                        : snapshot.topMemoryProcesses
                )
            }
            .frame(height: 144)

            // 第二行：STORAGE（含磁盘 R/W 速率）+ NETWORK（含上下行速率与端口占用表）
            HStack(spacing: 10) {
                StorageCard(stats: snapshot.disk) {
                    open(.analyze)
                }
                NetworkPortsCard(
                    stats: snapshot.network,
                    ports: snapshot.listeningPorts
                ) {
                    open(.network)
                }
            }
            .frame(height: 168)

            // 第三行：BATTERY（含整机实时功耗与适配器规格）+ 纯只读 THERMAL（温度趋势柱）
            HStack(spacing: 10) {
                BatteryCard(
                    stats: snapshot.battery,
                    power: snapshot.power
                )
                CompactThermalCard(
                    stats: snapshot.thermal,
                    history: monitor.thermalHistory
                )
            }
            .frame(height: 118)

            // 功能入口：Analyze / Uninstall
            actionsRow
                .padding(.top, 2)

            Rectangle()
                .fill(PanelPalette.divider)
                .frame(height: 1)

            // 底部工具栏：左刷新，右设置与退出
            footerBar
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 392)
        .background(PanelPalette.panelBackground)
        .background {
            PanelVisibilityReader { visible in
                monitor.setMode(visible ? .panelOpen : .background)
                if visible {
                    updater.checkOnLaunchIfNeeded()
                }
            }
        }
    }

    // MARK: - 功能入口与底部工具栏

    private var actionsRow: some View {
        HStack(spacing: 8) {
            PanelActionButton(title: Text("Analyze"), systemName: "chart.pie") {
                open(.analyze)
            }
            PanelActionButton(title: Text("Uninstall"), systemName: "trash") {
                open(.uninstall)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            PanelToolbarIconButton(
                systemName: "arrow.clockwise",
                label: Text("Refresh"),
                rotationDegrees: refreshRotation
            ) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    refreshRotation += 360
                }
                monitor.refreshNow()
            }

            Spacer()

            if let release = updater.availableRelease {
                Button {
                    open(.settings)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PanelPalette.cpuAccent)
                            .frame(width: 5, height: 5)
                        Text(verbatim: "v\(release.version)")
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PanelPalette.cpuAccent)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(PanelPalette.cpuAccent.opacity(0.14), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(PanelPalette.cpuAccent.opacity(0.45), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .help(Text("Update available: v\(release.version)"))
            }

            PanelToolbarIconButton(
                systemName: "gearshape",
                label: Text("Settings")
            ) {
                open(.settings)
            }

            PanelToolbarIconButton(
                systemName: "rectangle.portrait.and.arrow.right",
                label: Text("Quit Peek")
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct PanelActionButton: View {
    let title: Text
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 10.5, weight: .medium))
                title
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? PanelPalette.controlHover : PanelPalette.controlBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovered ? PanelPalette.controlBorderHover : PanelPalette.controlBorder,
                        lineWidth: 1)
            }
            .shadow(color: PanelPalette.cardShadow, radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct PanelToolbarIconButton: View {
    let systemName: String
    let label: Text
    var rotationDegrees: Double = 0
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13.5, weight: .regular))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                .frame(width: 26, height: 26)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelPalette.pillHover)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

#Preview("Bento Panel") {
    PanelView()
}
