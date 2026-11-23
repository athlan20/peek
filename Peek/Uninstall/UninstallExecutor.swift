import Foundation

/// 卸载的唯一执行入口：App 本体 + 勾选的残留，一律移到废纸篓。
struct UninstallExecutor: Sendable {
    var context: UninstallContext
    /// 移到废纸篓。默认用系统的 `trashItem`；测试时换成移到临时目录，避免往真实废纸篓里放东西。
    var trashHandler: @Sendable (URL) -> Bool = { url in
        (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    func uninstall(_ app: InstalledApp, residuals: [ResidualItem], isCancelled: @Sendable () -> Bool = { false }) -> UninstallOutcome {
        var outcome = UninstallOutcome()
        let ctx = context.clean

        // 再确认一次：不能卸载的、正在运行的都拒绝。
        if let reason = AppCatalog.blockReason(path: app.url.path, bundleID: app.bundleID, context: ctx) {
            outcome.appFailureReason = reason.rawValue
            return outcome
        }
        if let reason = CleanGuard.check(app.url, context: ctx, requireSameVolume: false) {
            outcome.appFailureReason = reason.rawValue
            return outcome
        }

        // 1. App 本体。失败就不动它的残留，避免留下一个没数据的空壳。
        if trash(app.url) || finderDelete(app.url) {
            outcome.appRemoved = true
            outcome.processed += 1
            outcome.freedBytes &+= app.bytes ?? 0
        } else {
            outcome.appFailureReason = "cannotRemoveApp"
            return outcome
        }

        // 2. 残留。
        for item in residuals {
            if isCancelled() { break }
            if let reason = revalidate(item) {
                outcome.skipped.append(CleanSkipped(path: item.url.path, reason: reason))
                continue
            }
            if trash(item.url) {
                outcome.processed += 1
                outcome.freedBytes &+= item.bytes
            } else {
                outcome.failed += 1
                outcome.skipped.append(CleanSkipped(path: item.url.path, reason: .noPermission))
            }
        }
        return outcome
    }

    /// 执行前重新检查（G11）。
    func revalidate(_ item: ResidualItem) -> CleanSkipReason? {
        if let reason = CleanGuard.check(item.url, context: context.clean) { return reason }
        guard let info = CleanFS.stat(item.url.path) else { return .changed }
        if let expected = item.fileID, info.fileID != expected { return .changed }
        return nil
    }

    // MARK: - 唯一的删除调用点

    private func trash(_ url: URL) -> Bool {
        trashHandler(url)
    }

    /// `trashItem` 被“App 管理”权限或管理员密码拦住时，交给 Finder（需要“自动化”授权）。
    private func finderDelete(_ url: URL) -> Bool {
        guard context.clean.allowsToolQueries else { return false }
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let command = ToolCommand(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", "tell application \"Finder\" to delete POSIX file \"\(escaped)\""],
            timeout: 120)
        return CleanToolRunner.run(command)
    }
}
