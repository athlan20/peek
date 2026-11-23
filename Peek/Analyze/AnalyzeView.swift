import AppKit
import SwiftUI

/// Analyze 独立窗口：沿用主面板的暗色 Bento 视觉语言，按大小看当前目录的子项（方块或列表），逐层进入；
/// “Agent”页只看各个 AI Agent 的目录；另有“下载”列表（`~/Downloads` 里 90 天没动过的）。
struct AnalyzeView: View {
    /// "文件""Agent"两页用方块还是列表。"下载"始终是列表。
    enum Layout: String {
        case treemap
        case list
    }

    @State private var model = AnalyzeModel()
    @AppStorage("analyze.layout") private var layout: Layout = .treemap

    private var tabAccent: Color {
        switch model.tab {
        case .items: PanelPalette.networkAccent
        case .agents: PanelPalette.cpuAccent
        case .oldDownloads: PanelPalette.thermalAccent
        }
    }

    private var tabGlow: Color {
        switch model.tab {
        case .items: PanelPalette.networkGlow
        case .agents: PanelPalette.cpuGlow
        case .oldDownloads: PanelPalette.thermalGlow
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            headerBar
            controlStrip
            contentCard
            footerBar
        }
        .padding(14)
        .frame(minWidth: 660, minHeight: 480)
        .background(PanelPalette.panelBackground)
        .toolbarBackground(PanelPalette.panelBackground, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        // 关窗口就停掉后台扫描。
        .onDisappear { model.stop() }
        .alert(
            Text("Delete “\(model.pendingTrash?.name ?? "")”?"),
            isPresented: Binding(
                get: { model.pendingTrash != nil },
                set: { if !$0 { model.pendingTrash = nil } }
            ),
            presenting: model.pendingTrash
        ) { _ in
            Button("Move to Trash", role: .destructive) { model.confirmTrash() }
            Button("Cancel", role: .cancel) { model.pendingTrash = nil }
        } message: { item in
            trashMessage(for: item)
        }
        .alert(
            Text(model.errorMessage ?? ""),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        }
    }

    // MARK: - 顶部导航与路径

    private var headerBar: some View {
        HStack(spacing: 8) {
            AnalyzeIconButton(
                systemName: "chevron.left",
                help: Text("Back"),
                isDisabled: !model.canGoBack
            ) {
                model.goBack()
            }

            // 面包屑路径条
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(model.stack.enumerated()), id: \.element.url) { index, listing in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(PanelPalette.textMuted)
                        }
                        let isCurrent = index == model.stack.count - 1
                        AnalyzeBreadcrumbButton(
                            title: crumbTitle(listing.url),
                            isCurrent: isCurrent
                        ) {
                            model.navigate(to: index)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PanelPalette.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }

            if model.tab == .items {
                Menu {
                    Button("Home") { model.open(AnalyzeModel.homeURL) }
                    Button("Applications") { model.open(AnalyzeModel.applicationsURL) }
                    Button("Startup Disk") { model.open(AnalyzeModel.startupDiskURL) }
                    Divider()
                    Button("Choose Folder…") { model.chooseFolder() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                        Text("Choose Location")
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
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if model.tab.isBrowsable, model.isScanning {
                AnalyzeIconButton(
                    systemName: model.isPaused ? "play.fill" : "pause.fill",
                    help: model.isPaused ? Text("Resume") : Text("Pause")
                ) {
                    model.togglePause()
                }
            }

            if model.canRefresh {
                AnalyzeIconButton(
                    systemName: "arrow.clockwise",
                    help: Text("Rescan")
                ) {
                    model.refresh()
                }
            }
        }
    }

    // MARK: - 页签、状态与视图切换

    private var controlStrip: some View {
        HStack(spacing: 10) {
            // 自定义暗色玻璃分段页签
            HStack(spacing: 3) {
                ForEach(AnalyzeModel.Tab.allCases) { tab in
                    let active = model.tab == tab
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            model.tab = tab
                        }
                    } label: {
                        Text(title(for: tab))
                            .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background {
                                if active {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(tabAccent.opacity(0.22))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(tabAccent.opacity(0.55), lineWidth: 1)
                                        }
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PanelPalette.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }

            statusPill

            Spacer(minLength: 8)

            if model.tab.isBrowsable {
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
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
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
                            .fill(Color.white.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusPill: some View {
        let isActiveScan = (model.tab.isBrowsable && model.isScanning && !model.isPaused)
            || (model.tab == .oldDownloads && model.isScanningDownloads)

        return HStack(spacing: 6) {
            Circle()
                .fill(isActiveScan ? tabAccent : PanelPalette.cpuAccent.opacity(0.75))
                .frame(width: 6, height: 6)
                .shadow(color: isActiveScan ? tabAccent.opacity(0.85) : .clear, radius: 3)

            if model.tab.isBrowsable, model.isScanning {
                if model.isPaused {
                    Text("Paused · \(sizeText(model.progress.scannedBytes)) · \(model.progress.itemCount) items")
                } else {
                    Text("Scanning… \(sizeText(model.progress.scannedBytes)) · \(model.progress.itemCount) items")
                }
            } else if model.tab == .oldDownloads, model.isScanningDownloads {
                Text("Scanning…")
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    scannedText(now: context.date)
                }
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(PanelPalette.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            Capsule()
                .fill(PanelPalette.cardBackground)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: - 主内容 Bento 容器

    private var contentCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            if model.rootInaccessible {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 24))
                        .foregroundStyle(PanelPalette.textMuted)
                    Text("This folder can’t be read.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.tab.isBrowsable, layout == .treemap {
                VStack(spacing: 0) {
                    AnalyzeTreemapView(
                        items: model.items,
                        isScanning: model.isScanning,
                        emptyText: model.tab == .agents ? Text("No AI agent data found.") : Text("Nothing to show."),
                        selection: $model.selection,
                        onEnter: { model.enter($0) },
                        onShowAll: { layout = .list },
                        onReveal: { model.reveal($0) },
                        onDelete: { model.requestTrash($0) })
                    if !model.items.isEmpty {
                        Rectangle()
                            .fill(PanelPalette.divider)
                            .frame(height: 1)
                        treemapLegendBar
                    }
                }
            } else {
                bentoList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(PanelPalette.cardBackground)
                .overlay {
                    LinearGradient(
                        colors: [tabGlow.opacity(0.28), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(shape)
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.75
                        )
                }
        }
        .overlay {
            shape
                .strokeBorder(tabAccent.opacity(0.35), lineWidth: 1)
        }
        .clipShape(shape)
    }

    private var treemapLegendBar: some View {
        HStack(spacing: 12) {
            if model.tab == .agents {
                legendItem(AnalyzeTreemapColors.color(for: .agent, agent: nil), "AI Agents")
            } else {
                legendItem(AnalyzeTreemapColors.color(for: .apps, agent: nil), "Apps")
                legendItem(AnalyzeTreemapColors.color(for: .developer, agent: nil), "Dev")
                legendItem(AnalyzeTreemapColors.color(for: .agent, agent: nil), "Agents")
                legendItem(AnalyzeTreemapColors.color(for: .media, agent: nil), "Media")
                legendItem(AnalyzeTreemapColors.color(for: .documents, agent: nil), "Docs")
                legendItem(AnalyzeTreemapColors.color(for: .system, agent: nil), "System")
                legendItem(PanelPalette.inactivePixel, "Other")
            }
            Spacer(minLength: 0)
            Text("\(model.items.count) items")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.16))
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                }
            Text(verbatim: title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PanelPalette.textSecondary)
        }
    }

    @ViewBuilder
    private var bentoList: some View {
        if model.visibleItems.isEmpty {
            VStack(spacing: 8) {
                if (model.tab.isBrowsable && model.isScanning) || (model.tab == .oldDownloads && model.isScanningDownloads) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(model.tab == .agents ? "No AI agent data found." : "Nothing to show.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.visibleItems) { item in
                        AnalyzeBentoRow(
                            item: item,
                            ratio: model.tab.isBrowsable && !item.isInaccessible ? ratio(item) : nil,
                            sizeLabel: sizeText(item.size),
                            barTint: categoryColor(for: item),
                            isSelected: model.selection == item.url,
                            onSelect: { model.selection = item.url },
                            onOpen: { open(item) }
                        )
                        .contextMenu {
                            if !model.directories(of: item).isEmpty {
                                AnalyzeItemMenu(
                                    item: item,
                                    onReveal: { model.reveal($0) },
                                    onDelete: { model.requestTrash($0) })
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - 底部操作栏

    private var footerBar: some View {
        let canAct = model.selectedItem.map { !model.directories(of: $0).isEmpty } ?? false

        return HStack(spacing: 10) {
            if let selected = model.selectedItem {
                HStack(spacing: 6) {
                    Circle()
                        .fill(categoryColor(for: selected))
                        .frame(width: 6, height: 6)
                    Text(verbatim: selected.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(PanelPalette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: sizeText(selected.size))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.textSecondary)
                }
            } else {
                Text("Double-click folder to open")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.textMuted)
            }

            Spacer(minLength: 8)

            AnalyzeFooterButton(
                title: Text("Reveal in Finder"),
                systemName: "folder",
                tint: PanelPalette.networkAccent,
                isDestructive: false,
                isDisabled: !canAct
            ) {
                model.revealSelected()
            }

            AnalyzeFooterButton(
                title: Text("Move to Trash"),
                systemName: "trash",
                tint: PanelPalette.alertAccent,
                isDestructive: true,
                isDisabled: !canAct
            ) {
                model.requestTrashSelected()
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 辅助

    private func categoryColor(for item: AnalyzeItem) -> Color {
        let home = AnalyzeModel.homeURL
        let agent = AnalyzeClassifier.agent(for: item.url, home: home)
        let category = AnalyzeClassifier.category(for: item.url, isDirectory: item.isDirectory, home: home)
        if agent != nil { return PanelPalette.cpuAccent }
        switch category {
        case .agent: return PanelPalette.cpuAccent
        case .apps: return PanelPalette.segOrange
        case .developer: return PanelPalette.segTeal
        case .media: return PanelPalette.memAccent
        case .documents: return PanelPalette.segYellow
        case .system: return PanelPalette.segBlue
        case .other: return PanelPalette.textSecondary
        }
    }

    /// 状态行：总量（逐层页）+ 上次扫描的时间。
    private func scannedText(now: Date) -> Text {
        let browsable = model.tab.isBrowsable
        let total = sizeText(model.totalBytes)
        guard let scannedAt = model.scannedAt else {
            return browsable ? Text("Total \(total)") : Text(verbatim: "")
        }
        if now.timeIntervalSince(scannedAt) < 60 {
            return browsable ? Text("Total \(total) · scanned just now") : Text("Scanned just now")
        }
        let relative = scannedAt.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
        return browsable ? Text("Total \(total) · scanned \(relative)") : Text("Scanned \(relative)")
    }

    /// 删除确认的正文：先说清要删的是什么、多大、在哪，再提醒用户自己判断，最后说明可以恢复。
    private func trashMessage(for item: AnalyzeItem) -> Text {
        let directories = model.directories(of: item)
        if item.url.isFileURL {
            let path = (item.url.path as NSString).abbreviatingWithTildeInPath
            return Text(
                "\(sizeText(item.size)) · \(path)\n\nMake sure you no longer need it. Peek only lists items by size and doesn’t check whether they’re safe to delete.\n\nIt will be moved to the Trash and can be restored until you empty the Trash."
            )
        }
        let total = directories.reduce(UInt64(0)) { $0 &+ $1.size }
        let list = directories.map { "\($0.name)  \(sizeText($0.size))" }.joined(separator: "\n")
        return Text(
            "Folders to be moved to the Trash (\(sizeText(total)) total):\n\(list)\n\nThey contain \(item.name)’s settings, sign-in data and session history. After deleting, you’ll need to sign in again and past sessions will be gone. Make sure you no longer need them.\n\nThey can be restored until you empty the Trash."
        )
    }

    private func open(_ item: AnalyzeItem) {
        if item.isDirectory, !item.isInaccessible {
            model.enter(item)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }

    private func ratio(_ item: AnalyzeItem) -> Double {
        let total = model.totalBytes
        guard total > 0 else { return 0 }
        return min(1, Double(item.size) / Double(total))
    }

    private func title(for tab: AnalyzeModel.Tab) -> LocalizedStringKey {
        switch tab {
        case .items: "Files"
        case .agents: "Agents"
        case .oldDownloads: "Downloads"
        }
    }

    private func crumbTitle(_ url: URL) -> String {
        if url == AnalyzeAgentScan.rootURL { return L10n.text("AI Agents") }
        if !url.isFileURL {
            return AnalyzeClassifier.agent(for: url, home: AnalyzeModel.homeURL)?.name ?? url.absoluteString
        }
        if url.path == "/" { return L10n.text("Startup Disk") }
        if url == AnalyzeModel.homeURL { return L10n.text("Home") }
        return url.lastPathComponent
    }

    private func sizeText(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .file))
    }
}

// MARK: - 暗色 Bento 辅助组件

private struct AnalyzeBreadcrumbButton: View {
    let title: String
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(
                    isCurrent || isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { isHovered = $0 }
    }
}

private struct AnalyzeBentoRow: View {
    let item: AnalyzeItem
    let ratio: Double?
    let sizeLabel: String
    let barTint: Color
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if item.url.isFileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PanelPalette.cpuAccent)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let ratio {
                    ThinMetricBar(fraction: ratio, tint: barTint)
                }
            }

            Spacer(minLength: 12)

            if item.isInaccessible {
                Text("No permission")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.textMuted)
            } else {
                HStack(spacing: 8) {
                    if let ratio {
                        Text(verbatim: String(format: "%.1f%%", ratio * 100))
                            .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                            .foregroundStyle(PanelPalette.textMuted)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text(verbatim: sizeLabel)
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                        .frame(minWidth: 56, alignment: .trailing)
                    if item.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(isHovered || isSelected ? PanelPalette.textSecondary : PanelPalette.textMuted.opacity(0.45))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? PanelPalette.networkAccent.opacity(0.18)
                        : (isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? PanelPalette.networkAccent.opacity(0.60)
                        : (isHovered ? Color.white.opacity(0.12) : Color.clear),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
    }
}

private struct AnalyzeIconButton: View {
    let systemName: String
    let help: Text
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(
                    isDisabled
                        ? PanelPalette.textMuted.opacity(0.5)
                        : (isHovered ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                )
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered && !isDisabled ? Color.white.opacity(0.10) : PanelPalette.cardBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isHovered && !isDisabled ? Color.white.opacity(0.22) : Color.white.opacity(0.10),
                            lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .onHover { isHovered = $0 }
    }
}

private struct AnalyzeFooterButton: View {
    let title: Text
    let systemName: String
    let tint: Color
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
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        if isDestructive { return PanelPalette.alertAccent.opacity(isHovered ? 0.22 : 0.12) }
        return isHovered ? Color.white.opacity(0.10) : PanelPalette.cardBackground
    }

    private var borderColor: Color {
        if isDisabled { return Color.white.opacity(0.06) }
        if isDestructive { return PanelPalette.alertAccent.opacity(isHovered ? 0.65 : 0.38) }
        return isHovered ? tint.opacity(0.50) : Color.white.opacity(0.12)
    }
}
