import SwiftUI

/// Network 独立窗口：展示所有已统计监听端口，支持按进程分组的方块拼图与列表两种视图，
/// 以及浏览器打开、复制地址、结束进程释放端口（带二次确认）。
struct NetworkView: View {
    enum Layout: String {
        case board
        case list
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var model = NetworkModel()
    @AppStorage("network.layout") private var layout: Layout = .board

    var monitor: SystemMonitor = .shared

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            categoryFilterBar
            contentCard
            footerBar
        }
        .padding(14)
        .frame(minWidth: 680, minHeight: 500)
        .background(PanelPalette.panelBackground)
        .toolbarBackground(PanelPalette.panelBackground, for: .windowToolbar)
        .onAppear { model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
        .alert(killAlertTitle, isPresented: $model.confirmingKill) {
            Button("Kill Process", role: .destructive) { model.confirmKill() }
            Button("Cancel", role: .cancel) { model.pendingKillPort = nil }
        } message: {
            Text(killAlertMessage)
        }
        .alert("Unable to Stop Process", isPresented: $model.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - 顶部工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PanelPalette.textMuted)
                TextField("Search port, process, PID", text: $model.search)
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

            // 实时上下行速率徽标
            HStack(spacing: 8) {
                rateChip(
                    arrow: "↓",
                    rate: monitor.snapshot.network.downBytesPerSecond,
                    color: PanelPalette.networkAccent
                )
                rateChip(
                    arrow: "↑",
                    rate: monitor.snapshot.network.upBytesPerSecond,
                    color: PanelPalette.memAccent
                )
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

            // 刷新按钮
            NetworkToolbarIconButton(
                systemName: "arrow.clockwise",
                help: Text("Refresh")
            ) {
                model.refreshNow()
                monitor.refreshNow()
            }

            // 方块 / 列表切换器
            HStack(spacing: 3) {
                layoutToggleButton(.board, systemName: "square.grid.2x2", help: Text("Block View"))
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

    private func rateChip(arrow: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: arrow)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: PanelFormat.rate(rate))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(PanelPalette.textPrimary)
        }
        .fixedSize()
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

    // MARK: - 分类筛选条

    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            filterPill(title: Text("All"), color: PanelPalette.networkAccent, count: model.ports.count, active: model.selectedCategory == nil) {
                model.selectedCategory = nil
            }

            ForEach(PortCategory.allCases, id: \.self) { category in
                let count = model.count(for: category)
                filterPill(
                    title: categoryLabel(category),
                    color: NetworkPortsCard.categoryColor(category),
                    count: count,
                    active: model.selectedCategory == category
                ) {
                    model.selectedCategory = (model.selectedCategory == category) ? nil : category
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func filterPill(
        title: Text,
        color: Color,
        count: Int,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                title
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? PanelPalette.textPrimary : PanelPalette.textSecondary)
                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(active ? color : PanelPalette.textMuted)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background {
                Capsule()
                    .fill(active ? color.opacity(0.16) : PanelPalette.cardBackground)
            }
            .overlay {
                Capsule()
                    .strokeBorder(active ? color.opacity(0.55) : PanelPalette.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryLabel(_ category: PortCategory) -> Text {
        switch category {
        case .web: Text("Web")
        case .ai: Text("AI")
        case .database: Text("DB")
        case .proxy: Text("Proxy")
        case .other: Text("Other")
        }
    }

    // MARK: - 主内容卡片

    private var contentCard: some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return VStack(spacing: 0) {
            if model.filteredPorts.isEmpty {
                emptyState
            } else {
                switch layout {
                case .board:
                    NetworkBoardView(
                        groups: model.groups,
                        selectedPortID: model.selectedPortID,
                        onSelect: { model.selectedPortID = $0.id },
                        onOpen: { model.openInBrowser($0) },
                        onCopy: { model.copyAddress($0) },
                        onReveal: { model.revealExecutable($0) },
                        onKill: { model.requestKill($0) }
                    )
                case .list:
                    portListView
                }
            }

            // 卡片底部图例与计数栏（对齐 Analyze / Uninstall）
            legendBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape
                .fill(PanelPalette.cardBackground)
                .overlay {
                    LinearGradient(
                        colors: [
                            PanelPalette.networkGlow.opacity(isLight ? 0.10 : 0.28),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }
        }
        .overlay {
            shape.strokeBorder(
                PanelPalette.networkAccent.opacity(isLight ? 0.30 : 0.45),
                lineWidth: 1
            )
        }
        .clipShape(shape)
        .shadow(color: PanelPalette.cardShadow, radius: isLight ? 4 : 0, x: 0, y: isLight ? 1 : 0)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.ports.isEmpty ? "network.slash" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(PanelPalette.textMuted)
            if model.ports.isEmpty {
                Text("No active dev ports")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelPalette.textSecondary)
            } else {
                Text("No matching ports")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 列表视图

    private var portListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.filteredPorts) { item in
                    NetworkPortListRow(
                        item: item,
                        isSelected: item.id == model.selectedPortID,
                        isCopied: item.id == model.copiedPortID,
                        onSelect: { model.selectedPortID = item.id },
                        onOpen: { model.openInBrowser(item) },
                        onCopy: { model.copyAddress(item) },
                        onKill: { model.requestKill(item) }
                    )
                }
            }
            .padding(10)
        }
    }

    // MARK: - 卡片内图例栏

    private var legendBar: some View {
        HStack(spacing: 12) {
            ForEach(PortCategory.allCases, id: \.self) { category in
                HStack(spacing: 4) {
                    Circle()
                        .fill(NetworkPortsCard.categoryColor(category))
                        .frame(width: 5.5, height: 5.5)
                    categoryLabel(category)
                        .font(.system(size: 10.5))
                        .foregroundStyle(PanelPalette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Text("\(model.filteredPorts.count) ports · \(model.groups.count) processes")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PanelPalette.legendBackground)
    }

    // MARK: - 底部详情与操作栏

    private var footerBar: some View {
        HStack(spacing: 8) {
            if let item = model.selectedPort {
                HStack(spacing: 6) {
                    Circle()
                        .fill(NetworkPortsCard.categoryColor(item.category))
                        .frame(width: 6, height: 6)
                    Text(verbatim: ":\(item.port)")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(PanelPalette.textPrimary)
                    Text(verbatim: "\(item.processName) · PID \(item.pid) · \(item.bindAddress)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(PanelPalette.textSecondary)
                        .lineLimit(1)
                    if item.establishedCount > 0 {
                        Text("· \(item.establishedCount) conn")
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(PanelPalette.segGreen)
                            .lineLimit(1)
                    }
                    if let path = item.executablePath {
                        Text(verbatim: "· \(path)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelPalette.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Text("Select a port, or double-click to open in browser")
                    .font(.system(size: 11))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let item = model.selectedPort {
                NetworkFooterButton(
                    title: Text("Open"),
                    systemName: "arrow.up.right.square",
                    disabled: !item.isWebOpenable
                ) {
                    model.openInBrowser(item)
                }

                NetworkFooterButton(
                    title: model.copiedPortID == item.id ? Text("Copied") : Text("Copy"),
                    systemName: model.copiedPortID == item.id ? "checkmark" : "doc.on.doc"
                ) {
                    model.copyAddress(item)
                }

                NetworkFooterButton(
                    title: Text("Kill Process"),
                    systemName: "xmark.octagon",
                    destructive: true
                ) {
                    model.requestKill(item)
                }
            } else {
                NetworkFooterButton(title: Text("Open"), systemName: "arrow.up.right.square", disabled: true) {}
                NetworkFooterButton(title: Text("Copy"), systemName: "doc.on.doc", disabled: true) {}
                NetworkFooterButton(title: Text("Kill Process"), systemName: "xmark.octagon", destructive: true, disabled: true) {}
            }
        }
        .frame(height: 28)
    }

    // MARK: - 终止确认文案

    private var killAlertTitle: Text {
        guard let item = model.pendingKillPort else { return Text("Kill Process?") }
        return Text("Kill \(item.processName) (PID \(String(item.pid)))?")
    }

    private var killAlertMessage: String {
        guard let item = model.pendingKillPort else { return "" }
        let affected = model.pendingKillAffectedPorts
        if affected.count > 1 {
            let portList = affected.map { ":\($0.port)" }.joined(separator: ", ")
            return String(
                format: L10n.text("This process is listening on multiple ports (%@). Stopping it will release all of them."),
                portList
            )
        }
        return String(
            format: L10n.text("This will send SIGTERM to %@ and release port :%d."),
            item.processName,
            Int32(item.port)
        )
    }
}

// MARK: - 列表视图单行

private struct NetworkPortListRow: View {
    let item: ListeningPort
    let isSelected: Bool
    let isCopied: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onKill: () -> Void

    @State private var isHovered = false

    private var color: Color {
        NetworkPortsCard.categoryColor(item.category)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)

            Text(verbatim: ":\(item.port)")
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(PanelPalette.textPrimary)
                .frame(width: 64, alignment: .leading)

            Text(verbatim: item.processName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PanelPalette.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 90, alignment: .leading)

            Text(verbatim: "PID \(item.pid)")
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(PanelPalette.textMuted)
                .frame(width: 72, alignment: .leading)

            Text(verbatim: NetworkPortsCard.categoryTag(item.category))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
                .frame(width: 44, alignment: .leading)

            Text(verbatim: item.bindAddress)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(PanelPalette.textSecondary)
                .lineLimit(1)

            if item.establishedCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(PanelPalette.segGreen)
                        .frame(width: 5, height: 5)
                    Text(verbatim: "\(item.establishedCount)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(PanelPalette.segGreen)
                }
            }

            Spacer(minLength: 4)

            if isHovered || isSelected {
                HStack(spacing: 4) {
                    if item.isWebOpenable {
                        rowIconButton("arrow.up.right.square", help: Text("Open in Browser"), action: onOpen)
                    }
                    rowIconButton(isCopied ? "checkmark" : "doc.on.doc", help: Text("Copy Address"), action: onCopy)
                    rowIconButton("xmark.octagon", tint: PanelPalette.alertAccent, help: Text("Kill Process"), action: onKill)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            shape.fill(
                isSelected
                    ? PanelPalette.rowSelected
                    : (isHovered ? PanelPalette.rowHover : PanelPalette.rowBackground)
            )
        }
        .overlay {
            shape.strokeBorder(
                isSelected ? PanelPalette.networkAccent.opacity(0.55) : PanelPalette.controlBorder.opacity(0.5),
                lineWidth: isSelected ? 1 : 0.75
            )
        }
        .contentShape(shape)
        .onTapGesture(count: 2) {
            onSelect()
            if item.isWebOpenable { onOpen() } else { onCopy() }
        }
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }

    private func rowIconButton(
        _ systemName: String,
        tint: Color = PanelPalette.textSecondary,
        help: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(PanelPalette.pillBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - 窗口专用控件按钮

private struct NetworkToolbarIconButton: View {
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
                        .fill(isHovered ? PanelPalette.controlHover : PanelPalette.cardBackground)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isHovered ? PanelPalette.controlBorderHover : PanelPalette.controlBorder,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

private struct NetworkFooterButton: View {
    let title: Text
    let systemName: String
    var destructive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let fg: Color = {
            if disabled { return PanelPalette.textMuted }
            if destructive { return PanelPalette.alertAccent }
            return PanelPalette.textPrimary
        }()

        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 10.5, weight: .medium))
                title
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        destructive && !disabled
                            ? PanelPalette.alertAccent.opacity(isHovered ? 0.20 : 0.12)
                            : (isHovered && !disabled ? PanelPalette.controlHover : PanelPalette.cardBackground)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        destructive && !disabled
                            ? PanelPalette.alertAccent.opacity(isHovered ? 0.65 : 0.40)
                            : (isHovered && !disabled ? PanelPalette.controlBorderHover : PanelPalette.controlBorder),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .onHover { isHovered = $0 }
    }
}
