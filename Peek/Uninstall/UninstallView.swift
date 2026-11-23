import AppKit
import SwiftUI

/// Uninstall 独立窗口：沿用主面板与分析窗口的暗色 Bento 视觉语言。
struct UninstallView: View {
    /// App 列表用方块还是列表。"预览残留"页始终是列表。
    enum Layout: String {
        case treemap
        case list
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var model = UninstallModel()
    @AppStorage("uninstall.layout") private var layout: Layout = .treemap
    /// 方块视图里选中的 App。切换视图、进出预览页都保留。
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .list: listView
            case .previewing: previewView
            case .uninstalling: uninstallingView
            case .done: resultView
            }
        }
        .padding(14)
        .frame(minWidth: 660, minHeight: 480)
        .background(PanelPalette.panelBackground)
        .toolbarBackground(PanelPalette.panelBackground, for: .windowToolbar)
        .onAppear { model.load() }
        .alert("Uninstall \(model.current?.name ?? "")?", isPresented: $model.confirming) {
            Button("Uninstall", role: .destructive) { model.confirmedUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.includesPersonalData
                 ? "The app and the selected files go to the Trash. Personal data is included — restore it from the Trash if you need it back."
                 : "The app and the selected files go to the Trash. You can restore them from there.")
        }
    }

    // MARK: - 主列表 / 方块视图

    private var listView: some View {
        VStack(spacing: 10) {
            toolbar
            contentCard
            if layout == .treemap {
                treemapFooter
            }
        }
        .onChange(of: model.apps.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // 暗色玻璃搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PanelPalette.textMuted)
                TextField("Search", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(PanelPalette.textPrimary)
                if !model.search.isEmpty {
                    Button {
                        model.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PanelPalette.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(PanelPalette.controlBorder, lineWidth: 1)
            }

            if layout == .list {
                Menu {
                    Button("Name") { model.sortKey = .name }
                    Button("Size") { model.sortKey = .size }
                    Button("Last Used") { model.sortKey = .lastUsed }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(sortKeyTitle(model.sortKey))
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                    .foregroundStyle(PanelPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PanelPalette.cardBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PanelPalette.controlBorder, lineWidth: 1)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if model.isMeasuring {
                UninstallIconButton(
                    systemName: model.isPaused ? "play.fill" : "pause.fill",
                    help: model.isPaused ? Text("Resume") : Text("Pause")
                ) {
                    model.togglePause()
                }
            }

            UninstallIconButton(
                systemName: "arrow.clockwise",
                help: Text("Refresh")
            ) {
                model.reload()
            }

            // Treemap / List 暗色切换器
            HStack(spacing: 3) {
                layoutToggleButton(.treemap, systemName: "square.grid.2x2", help: Text("Treemap"))
                layoutToggleButton(.list, systemName: "list.bullet", help: Text("List"))
            }
            .padding(3)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PanelPalette.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(PanelPalette.controlBorder, lineWidth: 1)
            }
        }
    }

    private func layoutToggleButton(_ target: Layout, systemName: String, help: Text) -> some View {
        let active = layout == target
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                layout = target
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                .frame(width: 26, height: 22)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PanelPalette.segmentedActive)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var contentCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            if model.isLoading && model.apps.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading apps…")
                        .font(.system(size: 12))
                        .foregroundStyle(PanelPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layout == .treemap {
                VStack(spacing: 0) {
                    UninstallTreemapView(
                        apps: model.visibleApps,
                        selectedID: $selectedID,
                        onPreview: { model.preview($0) },
                        onShowAll: { layout = .list })
                    Rectangle()
                        .fill(PanelPalette.divider)
                        .frame(height: 1)
                    treemapLegend
                }
            } else {
                bentoAppList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            let isLight = colorScheme == .light
            shape
                .fill(PanelPalette.cardBackground)
                .overlay {
                    LinearGradient(
                        colors: [PanelPalette.memGlow.opacity(isLight ? 0.08 : 0.24), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(shape)
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(isLight ? 0.85 : 0.14), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.75
                        )
                }
        }
        .overlay {
            shape
                .strokeBorder(PanelPalette.memAccent.opacity(0.32), lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: PanelPalette.cardShadow, radius: colorScheme == .light ? 3 : 0, x: 0, y: colorScheme == .light ? 1 : 0)
    }

    private var bentoAppList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.visibleApps) { app in
                    UninstallBentoAppRow(
                        app: app,
                        sizeLabel: app.bytes.map(size),
                        blockedText: app.blocked.map { blockText($0) },
                        isSelected: selectedID == app.id,
                        onSelect: { selectedID = app.id },
                        onPreview: { model.preview(app) }
                    )
                    .contextMenu {
                        Button("Uninstall…") { model.preview(app) }
                            .disabled(app.blocked != nil)
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([app.url])
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var treemapLegend: some View {
        HStack(spacing: 10) {
            ForEach(UninstallUsageBand.allCases, id: \.self) { band in
                HStack(spacing: 4) {
                    Circle()
                        .fill(UninstallTreemapColors.color(band))
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle().strokeBorder(PanelPalette.treemapTileBorder, lineWidth: 0.5)
                        }
                    Text(band.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PanelPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if model.isMeasuring {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isPaused ? PanelPalette.thermalAccent : PanelPalette.cpuAccent)
                        .frame(width: 5, height: 5)
                    if model.isPaused {
                        Text("Paused · \(model.pendingCount) apps left")
                    } else {
                        Text("Measuring sizes… \(model.pendingCount) apps left")
                    }
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textMuted)
                .lineLimit(1)
            } else {
                Text("\(model.visibleApps.count) apps")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PanelPalette.legendBackground)
    }

    private var treemapFooter: some View {
        HStack(spacing: 10) {
            if let app = selectedApp {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(verbatim: app.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PanelPalette.textPrimary)
                        .lineLimit(1)
                    if let bytes = app.bytes {
                        Text(verbatim: size(bytes))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.textSecondary)
                    }
                    if let reason = app.blocked {
                        Text(blockText(reason))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(PanelPalette.thermalAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PanelPalette.thermalAccent.opacity(0.15), in: Capsule())
                    }
                }
            } else {
                Text("Select an app or double-click to review leftovers")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.textMuted)
            }

            Spacer(minLength: 8)

            if let app = selectedApp {
                UninstallActionButton(
                    title: Text("Reveal in Finder"),
                    systemName: "folder",
                    isDestructive: false,
                    isDisabled: false
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }

                UninstallActionButton(
                    title: Text("Uninstall…"),
                    systemName: "trash",
                    isDestructive: true,
                    isDisabled: app.blocked != nil
                ) {
                    model.preview(app)
                }
                .help(app.blocked.map { blockText($0) } ?? "")
            }
        }
        .frame(minHeight: 28)
        .padding(.top, 2)
    }

    private var selectedApp: InstalledApp? {
        guard let selectedID else { return nil }
        return model.apps.first { $0.id == selectedID }
    }

    // MARK: - 预览残留页

    private var previewView: some View {
        VStack(spacing: 10) {
            // 顶部返回栏
            HStack(spacing: 8) {
                UninstallActionButton(
                    title: Text("Back"),
                    systemName: "chevron.left",
                    isDestructive: false,
                    isDisabled: false
                ) {
                    model.backToList()
                }
                Spacer()
                Text("Review Leftover Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelPalette.textSecondary)
                Spacer()
                Color.clear.frame(width: 68, height: 1)
            }

            if let app = model.current {
                // 目标 App 概览卡片
                BentoCard(borderColor: PanelPalette.memAccent, topGlow: PanelPalette.memGlow) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: app.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PanelPalette.textPrimary)
                            Text(verbatim: app.url.path)
                                .font(.system(size: 10.5))
                                .foregroundStyle(PanelPalette.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let bytes = app.bytes {
                            Text(verbatim: size(bytes))
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(PanelPalette.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(PanelPalette.pillBackground, in: Capsule())
                        }
                    }
                }
                .frame(height: 62)

                // 残留列表 Bento 容器
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                Group {
                    if model.isFindingResiduals {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking for leftover files…")
                                .font(.system(size: 12))
                                .foregroundStyle(PanelPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.residuals.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 22))
                                .foregroundStyle(PanelPalette.cpuAccent)
                            Text("No leftover files found.")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(PanelPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(ResidualCategory.allCases, id: \.self) { category in
                                    let items = model.residuals.filter { $0.category == category }
                                    if !items.isEmpty {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(categoryTitle(category))
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(PanelPalette.textMuted)
                                                .padding(.horizontal, 6)
                                            ForEach(items) { residualRow($0) }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(PanelPalette.cardBackground))
                .overlay(shape.strokeBorder(PanelPalette.controlBorder, lineWidth: 1))
                .clipShape(shape)
            }

            // 底部确认栏
            HStack {
                Text("\(size(model.selectedBytes)) will be moved to the Trash")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(PanelPalette.textSecondary)
                Spacer()
                UninstallActionButton(
                    title: Text("Uninstall…"),
                    systemName: "trash",
                    isDestructive: true,
                    isDisabled: model.isFindingResiduals
                ) {
                    model.requestUninstall()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
    }

    private func residualRow(_ item: ResidualItem) -> some View {
        let isSelected = model.selectedResiduals.contains(item.id)
        return HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { model.setSelected($0, item) }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: item.url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PanelPalette.textPrimary)
                        .lineLimit(1)
                    if item.category == .personalData {
                        Text("May contain your data")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(PanelPalette.thermalAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(PanelPalette.thermalAccent.opacity(0.16), in: Capsule())
                    }
                    if item.matchedByName {
                        Text("Matched by name")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(PanelPalette.textMuted)
                    }
                }
                Text(verbatim: item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if item.unreadable {
                Text("No permission")
                    .font(.system(size: 10.5))
                    .foregroundStyle(PanelPalette.textMuted)
            }
            Text(verbatim: size(item.bytes))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? PanelPalette.rowSelected : PanelPalette.rowBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? PanelPalette.controlBorderHover : PanelPalette.pillBorder, lineWidth: 1)
        }
    }

    // MARK: - 卸载中 & 结果页

    private var uninstallingView: some View {
        BentoCard(borderColor: PanelPalette.memAccent, topGlow: PanelPalette.memGlow) {
            VStack(spacing: 12) {
                ProgressView()
                Text("Moving to the Trash…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelPalette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var resultView: some View {
        let outcome = model.outcome ?? UninstallOutcome()
        let border = outcome.appRemoved ? PanelPalette.cpuAccent : PanelPalette.alertAccent
        let glow = outcome.appRemoved ? PanelPalette.cpuGlow : PanelPalette.alertGlow

        return BentoCard(borderColor: border, topGlow: glow) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: outcome.appRemoved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(border)
                    Text(outcome.appRemoved
                         ? "Uninstalled \(model.current?.name ?? "")"
                         : "Couldn’t uninstall \(model.current?.name ?? "")")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PanelPalette.textPrimary)
                }

                Rectangle().fill(PanelPalette.divider).frame(height: 1)

                if outcome.appRemoved {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Freed \(size(outcome.freedBytes))")
                            .font(.system(size: 24, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.cpuAccent)
                        Text("\(outcome.processed) items moved to the Trash")
                            .font(.system(size: 12))
                            .foregroundStyle(PanelPalette.textSecondary)
                        if outcome.failed > 0 {
                            Text("\(outcome.failed) failed")
                                .font(.system(size: 11.5))
                                .foregroundStyle(PanelPalette.thermalAccent)
                        }
                        if !outcome.skipped.isEmpty {
                            Text("\(outcome.skipped.count) skipped")
                                .font(.system(size: 11.5))
                                .foregroundStyle(PanelPalette.textMuted)
                        }
                    }
                } else {
                    Text(failureText(outcome.appFailureReason))
                        .font(.system(size: 12.5))
                        .foregroundStyle(PanelPalette.textSecondary)
                }

                Spacer()

                HStack {
                    Spacer()
                    UninstallActionButton(
                        title: Text("Done"),
                        systemName: "checkmark",
                        isDestructive: false,
                        isDisabled: false
                    ) {
                        model.finish()
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - 文案

    private func sortKeyTitle(_ key: UninstallModel.SortKey) -> LocalizedStringKey {
        switch key {
        case .name: "Name"
        case .size: "Size"
        case .lastUsed: "Last Used"
        }
    }

    private func blockText(_ reason: UninstallBlockReason) -> LocalizedStringKey {
        switch reason {
        case .systemApp: "System app"
        case .peekItself: "Peek can’t uninstall itself"
        case .appleApp: "Apple system app"
        case .vendorManaged: "Use the vendor’s own uninstaller"
        case .running: "Running — quit it first"
        }
    }

    private func categoryTitle(_ c: ResidualCategory) -> LocalizedStringKey {
        switch c {
        case .settings: "Settings"
        case .cache: "Caches and Logs"
        case .launchAgent: "Login Items"
        case .personalData: "Personal Data"
        }
    }

    private func failureText(_ reason: String?) -> LocalizedStringKey {
        switch reason {
        case "cannotRemoveApp": "The app couldn’t be moved to the Trash, so nothing else was removed."
        case UninstallBlockReason.running.rawValue: "The app is running. Quit it and try again."
        default: "Nothing was removed."
        }
    }

    private func size(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .file))
    }
}

// MARK: - 暗色 Bento 辅助组件

private struct UninstallBentoAppRow: View {
    let app: InstalledApp
    let sizeLabel: String?
    let blockedText: LocalizedStringKey?
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(verbatim: app.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textPrimary)
                        .lineLimit(1)
                    if app.isAppStore {
                        Image(systemName: "applelogo")
                            .font(.system(size: 9.5))
                            .foregroundStyle(PanelPalette.textMuted)
                            .help(Text("From the App Store"))
                    }
                }
                if let blockedText {
                    Text(blockedText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(PanelPalette.thermalAccent)
                } else {
                    Text(verbatim: app.bundleID)
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelPalette.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let sizeLabel {
                    Text(verbatim: sizeLabel)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.textPrimary)
                } else {
                    ProgressView().controlSize(.mini)
                }
                if let used = app.lastUsed {
                    Text(used, format: .relative(presentation: .named))
                        .font(.system(size: 10))
                        .foregroundStyle(PanelPalette.textMuted)
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelPalette.textMuted)
                }
            }

            UninstallActionButton(
                title: Text("Uninstall…"),
                systemName: "trash",
                isDestructive: true,
                isDisabled: app.blocked != nil
            ) {
                onPreview()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? PanelPalette.memAccent.opacity(0.16)
                        : (isHovered ? PanelPalette.rowHover : PanelPalette.rowBackground)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? PanelPalette.memAccent.opacity(0.55)
                        : (isHovered ? PanelPalette.controlBorder : Color.clear),
                    lineWidth: 1
                )
        }
        .opacity(app.blocked == nil || app.blocked == .running ? 1 : 0.58)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            if app.blocked == nil { onPreview() }
        }
        .onTapGesture { onSelect() }
    }
}

private struct UninstallIconButton: View {
    let systemName: String
    let help: Text
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                .frame(width: 28, height: 28)
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
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}

private struct UninstallActionButton: View {
    let title: Text
    let systemName: String
    let isDestructive: Bool
    let isDisabled: Bool
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
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        if isDisabled { return PanelPalette.textMuted.opacity(0.55) }
        if isDestructive { return PanelPalette.alertAccent }
        return isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary
    }

    private var backgroundColor: Color {
        if isDisabled { return PanelPalette.cardBackground.opacity(0.6) }
        if isDestructive { return PanelPalette.alertAccent.opacity(isHovered ? 0.18 : 0.10) }
        return isHovered ? PanelPalette.controlHover : PanelPalette.controlBackground
    }

    private var borderColor: Color {
        if isDisabled { return PanelPalette.pillBorder.opacity(0.7) }
        if isDestructive { return PanelPalette.alertAccent.opacity(isHovered ? 0.60 : 0.35) }
        return isHovered ? PanelPalette.controlBorderHover : PanelPalette.controlBorder
    }
}
