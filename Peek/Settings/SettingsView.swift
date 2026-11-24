import SwiftUI

/// Settings 独立窗口：沿用 Bento 视觉风格，保留核心设置项（外观、语言、刷新间隔、开机启动、完全磁盘访问、在线更新）。
struct SettingsView: View {
    @State private var model = SettingsModel()
    private var updater: UpdateManager = .shared
    private var languageManager: LanguageManager = .shared
    private var appearanceManager: AppearanceManager = .shared
    private var menuBarMetricManager: MenuBarMetricManager = .shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                generalCard
                fullDiskAccessCard
                updateCard
            }
            .padding(14)
        }
        .frame(minWidth: 460, minHeight: 430)
        .background(PanelPalette.panelBackground)
        .toolbarBackground(PanelPalette.panelBackground, for: .windowToolbar)
        .onAppear { model.reloadFullDiskAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadFullDiskAccess()
        }
    }

    // MARK: - 通用设置（外观 + 语言 + 刷新间隔 + 开机启动）

    private var generalCard: some View {
        BentoCard(borderColor: PanelPalette.networkAccent, topGlow: PanelPalette.networkGlow) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GENERAL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PanelPalette.textSecondary)

                // 外观模式
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                        Text("Follow system or choose a theme")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(AppAppearance.allCases) { option in
                            let active = appearanceManager.appearance == option
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    appearanceManager.setAppearance(option)
                                }
                            } label: {
                                Text(option.titleKey)
                                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                                    .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 22)
                                    .background {
                                        if active {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(PanelPalette.networkAccent.opacity(0.18))
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .strokeBorder(PanelPalette.networkAccent.opacity(0.48), lineWidth: 1)
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
                            .fill(PanelPalette.segmentedTrack)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PanelPalette.pillBorder, lineWidth: 1)
                    }
                }

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

                // 界面语言
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Language")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                        Text("Applies immediately without relaunch")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(AppLanguage.allCases) { option in
                            let active = languageManager.language == option
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    languageManager.setLanguage(option)
                                }
                            } label: {
                                Text(verbatim: option.displayTitle(locale: languageManager.locale))
                                    .font(.system(size: 11, weight: active ? .semibold : .medium))
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
                            .fill(PanelPalette.segmentedTrack)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PanelPalette.pillBorder, lineWidth: 1)
                    }
                }

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

                // 菜单栏显示指标
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu bar")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                        Text("Metric shown beside the icon")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(MenuBarMetric.allCases) { option in
                            let active = menuBarMetricManager.metric == option
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    menuBarMetricManager.setMetric(option)
                                }
                            } label: {
                                Text(option.titleKey)
                                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                                    .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                                    .padding(.horizontal, 8)
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
                            .fill(PanelPalette.segmentedTrack)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PanelPalette.pillBorder, lineWidth: 1)
                    }
                }

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

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
                            .fill(PanelPalette.segmentedTrack)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PanelPalette.pillBorder, lineWidth: 1)
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

    // MARK: - 在线更新

    private var updateCard: some View {
        let hasUpdate = updater.availableRelease != nil
        let border = hasUpdate ? PanelPalette.cpuAccent : PanelPalette.storageBorder
        let glow = hasUpdate ? PanelPalette.cpuGlow : PanelPalette.storageGlow

        return BentoCard(borderColor: border, topGlow: glow) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("UPDATES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(PanelPalette.textSecondary)
                    Spacer()
                    Text(verbatim: "v\(updater.currentVersion) · \(UpdateManager.currentArch)")
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.textMuted)
                }

                updateStatusContent

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

                Toggle(isOn: autoUpdateBinding) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check for updates automatically")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PanelPalette.textPrimary)
                        Text("Silently checks GitHub Releases once per day")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(PanelPalette.cpuAccent)
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private var updateStatusContent: some View {
        switch updater.state {
        case .idle:
            HStack {
                Text("Check GitHub Releases for newer versions.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PanelPalette.textSecondary)
                Spacer()
                SettingsPillButton(title: Text("Check Now"), systemName: "arrow.clockwise") {
                    updater.checkForUpdates(manual: true)
                }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PanelPalette.textSecondary)
                Spacer()
            }

        case .upToDate:
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(PanelPalette.cpuAccent).frame(width: 6, height: 6)
                    Text("Peek is up to date.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textPrimary)
                }
                Spacer()
                SettingsPillButton(title: Text("Check Again"), systemName: "arrow.clockwise") {
                    updater.checkForUpdates(manual: true)
                }
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(PanelPalette.cpuAccent).frame(width: 6, height: 6)
                        Text("v\(release.version) available")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PanelPalette.cpuAccent)
                    }
                    Spacer()
                    SettingsPillButton(title: Text("Release Notes"), systemName: "arrow.up.right") {
                        updater.openReleasePage(release)
                    }
                    SettingsPillButton(title: Text("Update & Relaunch"), systemName: "arrow.down.circle.fill") {
                        updater.downloadAndInstall(release)
                    }
                }
                if !release.notes.isEmpty {
                    Text(verbatim: release.notes)
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelPalette.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .downloading(let release, let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading v\(release.version)…")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textPrimary)
                    Spacer()
                    Text(verbatim: "\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PanelPalette.cpuAccent)
                }
                ProgressView(value: progress)
                    .tint(PanelPalette.cpuAccent)
            }

        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Verifying signature & checksum…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PanelPalette.textSecondary)
                Spacer()
            }

        case .relaunching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing update & relaunching…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PanelPalette.cpuAccent)
                Spacer()
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(verbatim: message)
                        .font(.system(size: 11))
                        .foregroundStyle(PanelPalette.thermalAccent)
                        .lineLimit(2)
                    Spacer()
                    SettingsPillButton(title: Text("Retry"), systemName: "arrow.clockwise") {
                        updater.checkForUpdates(manual: true)
                    }
                }
            }
        }
    }

    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { updater.autoCheckEnabled },
            set: { updater.autoCheckEnabled = $0 }
        )
    }
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
                    .fill(isHovered ? PanelPalette.pillHover : PanelPalette.pillBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovered ? PanelPalette.controlBorderHover : PanelPalette.controlBorder,
                        lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
