import SwiftUI

/// Settings 独立窗口：沿用暗色 Bento 视觉风格，只保留核心设置项（刷新间隔、开机启动、完全磁盘访问、最近记录）。
struct SettingsView: View {
    @State private var model = SettingsModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                generalCard
                fullDiskAccessCard
                historyCard
            }
            .padding(14)
        }
        .frame(minWidth: 480, minHeight: 380)
        .background(PanelPalette.panelBackground)
        .toolbarBackground(PanelPalette.panelBackground, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .onAppear { model.reloadFullDiskAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadFullDiskAccess()
        }
    }

    // MARK: - 通用设置（刷新间隔 + 开机启动）

    private var generalCard: some View {
        BentoCard(borderColor: PanelPalette.networkAccent, topGlow: PanelPalette.networkGlow) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GENERAL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PanelPalette.textSecondary)

                // 刷新间隔
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refresh interval")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                        Text("Panel telemetry sampling rate")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(SettingsStore.refreshIntervalOptions, id: \.self) { seconds in
                            let active = model.refreshInterval == seconds
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    model.setRefreshInterval(seconds)
                                }
                            } label: {
                                Text(intervalShortTitle(seconds))
                                    .font(.system(size: 11, weight: active ? .semibold : .medium).monospacedDigit())
                                    .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 22)
                                    .background {
                                        if active {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(PanelPalette.networkAccent.opacity(0.24))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .strokeBorder(PanelPalette.networkAccent.opacity(0.55), lineWidth: 1)
                                                }
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

                // 开机启动
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: launchAtLoginSelection) {
                        Text("Launch at login")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(PanelPalette.cpuAccent)

                    if model.launchAtLoginFailed {
                        Text("Couldn’t set launch at login. Add Peek manually in System Settings → Login Items.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.thermalAccent)
                    }
                }
            }
            .padding(2)
        }
    }

    private var launchAtLoginSelection: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) })
    }

    private func intervalShortTitle(_ seconds: Int) -> String {
        "\(seconds)s"
    }

    // MARK: - 完全磁盘访问

    private var fullDiskAccessCard: some View {
        let authorized = model.hasFullDiskAccess
        let border = authorized ? PanelPalette.cpuAccent : PanelPalette.thermalAccent
        let glow = authorized ? PanelPalette.cpuGlow : PanelPalette.thermalGlow

        return BentoCard(borderColor: border, topGlow: glow) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FULL DISK ACCESS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(PanelPalette.textSecondary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(border)
                            .frame(width: 6, height: 6)
                        Text(authorized ? "Authorized" : "Not Authorized")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(border)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(border.opacity(0.14), in: Capsule())
                }

                if !authorized {
                    Text("With Full Disk Access, Peek can measure protected folders accurately during analysis and uninstall.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(PanelPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsPillButton(title: Text("Open System Settings"), systemName: "lock.open") {
                        model.openFullDiskAccessSettings()
                    }
                }
            }
            .padding(2)
        }
    }

    // MARK: - 最近的历史记录

    private var historyCard: some View {
        let entries = Array(HistoryStore.shared.entries.prefix(10))

        return BentoCard(borderColor: PanelPalette.storageBorder, topGlow: PanelPalette.storageGlow) {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT HISTORY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PanelPalette.textSecondary)

                if entries.isEmpty {
                    Text("No history yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(PanelPalette.textMuted)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .padding(2)
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            Text(kindTitle(entry.kind))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(PanelPalette.textPrimary)
                .frame(width: 72, alignment: .leading)
            Text(verbatim: Self.relativeFormatter.localizedString(for: entry.date, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(PanelPalette.textMuted)
            Spacer(minLength: 8)
            Text("\(entry.itemCount) items")
                .font(.system(size: 11))
                .foregroundStyle(PanelPalette.textSecondary)
            if entry.freedBytes > 0 {
                Text(verbatim: Int64(clamping: entry.freedBytes).formatted(.byteCount(style: .file)))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PanelPalette.cpuAccent)
            }
            if entry.failedCount > 0 {
                Text("\(entry.failedCount) failed")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.thermalAccent)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.03))
        }
    }

    private func kindTitle(_ kind: HistoryKind) -> LocalizedStringKey {
        switch kind {
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        }
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()
}

private struct SettingsPillButton: View {
    let title: Text
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .medium))
                title
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.12),
                        lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
