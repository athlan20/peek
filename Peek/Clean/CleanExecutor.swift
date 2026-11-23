import Foundation

/// 清理的唯一删除入口。别的地方不直接调用 `removeItem` / `trashItem`。
///
/// 每一项执行前都重新做一遍检查（G11）：路径安全、白名单、App 是否在运行、
/// 最近是否被用过，并确认还是扫描时的那个文件（类型和设备号、inode 没变）。
struct CleanExecutor: Sendable {
    var context: CleanContext

    /// 执行选中的组。`isCancelled` 为 true 时停下，已删的不回滚。
    func execute(
        _ groups: [CleanGroup],
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (Int) -> Void = { _ in }
    ) -> CleanOutcome {
        var outcome = CleanOutcome()
        for group in groups {
            if isCancelled() { outcome.wasCancelled = true; break }
            run(group, outcome: &outcome, isCancelled: isCancelled, progress: progress)
        }
        return outcome
    }

    // MARK: - 一组

    private func run(
        _ group: CleanGroup,
        outcome: inout CleanOutcome,
        isCancelled: @Sendable () -> Bool,
        progress: @Sendable (Int) -> Void
    ) {
        func skipAll(_ reason: CleanSkipReason) {
            outcome.skipped.append(CleanSkipped(path: group.title, reason: reason))
        }

        for bundleID in group.requiresNotRunning where CleanGuard.isExactlyRunning(bundleID, context: context) {
            skipAll(group.ruleID == .r5 ? .appRunning : .browserRunning)
            return
        }
        if !group.blockingProcessFragments.isEmpty {
            guard let names = context.runningProcessNames else { skipAll(.appRunning); return }
            let lowered = names.map { $0.lowercased() }
            for fragment in group.blockingProcessFragments where lowered.contains(where: { $0.contains(fragment.lowercased()) }) {
                skipAll(.appRunning)
                return
            }
        }

        switch group.method {
        case .finderEmptyTrash:
            let command = ToolCommand(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", "tell application \"Finder\" to empty the trash"],
                timeout: 120)
            if CleanToolRunner.run(command) {
                outcome.processed += 1
                outcome.freedBytes &+= group.bytes
            } else {
                outcome.failed += 1
                outcome.skipped.append(CleanSkipped(path: group.title, reason: .failed))
            }
            progress(outcome.processed)

        case .tool(let command):
            guard FileManager.default.isExecutableFile(atPath: command.executable.path) else {
                skipAll(.toolMissing)
                return
            }
            if CleanToolRunner.run(command) {
                outcome.processed += max(1, group.items.count)
                // 工具清多少取决于它自己（如 pnpm 只清没引用的包），所以重新量一遍算释放了多少。
                var after: UInt64 = 0
                var measure = CleanMeasure()
                for item in group.items { after &+= measure.measure(item.url).bytes }
                outcome.freedBytes &+= group.bytes > after ? group.bytes - after : 0
            } else {
                outcome.failed += 1
                outcome.skipped.append(CleanSkipped(path: group.title, reason: .failed))
            }
            progress(outcome.processed)

        case .remove, .trash:
            for item in group.items {
                if isCancelled() { outcome.wasCancelled = true; return }
                if let reason = revalidate(item) {
                    outcome.skipped.append(CleanSkipped(path: item.url.path, reason: reason))
                    continue
                }
                if perform(group.method, at: item.url) {
                    outcome.processed += 1
                    outcome.freedBytes &+= item.bytes
                } else {
                    outcome.failed += 1
                    outcome.skipped.append(CleanSkipped(path: item.url.path, reason: .noPermission))
                }
                progress(outcome.processed)
            }
        }
    }

    // MARK: - G11 重新校验

    /// 返回跳过原因，nil 表示可以删。
    func revalidate(_ item: CleanItem) -> CleanSkipReason? {
        if let reason = CleanGuard.check(item.url, context: context) { return reason }
        guard let info = CleanFS.stat(item.url.path) else { return .changed }
        if let expected = item.fileID, info.fileID != expected { return .changed }
        if info.isDirectory != item.isDirectory && !info.isSymlink { return .changed }
        if let id = item.bundleID, CleanGuard.isAppRunning(id, context: context) { return .appRunning }
        if item.appliesRecentCheck {
            var measure = CleanMeasure()
            let fresh = measure.measure(item.url)
            if CleanGuard.isRecentlyUsed(fresh.newestModified, context: context) { return .recentlyUsed }
        }
        return nil
    }

    // MARK: - 唯一的删除调用点

    private func perform(_ method: CleanDeleteMethod, at url: URL) -> Bool {
        do {
            switch method {
            case .remove:
                // 对符号链接只删链接本身。
                try FileManager.default.removeItem(at: url)
            case .trash:
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            case .tool, .finderEmptyTrash:
                return false
            }
            return true
        } catch {
            return false
        }
    }
}

/// 读管道的结果。只在读完（信号量发出）之后才被另一个线程读取。
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}

/// 调用工具命令。绝对路径、有超时、捕获退出码，不经过 shell。
enum CleanToolRunner {
    /// 成功（退出码 0）返回 true。
    static func run(_ command: ToolCommand) -> Bool {
        output(command) != nil
    }

    /// 成功时返回标准输出，失败或超时返回 nil。
    static func output(_ command: ToolCommand) -> String? {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        // 先读输出，避免管道写满把子进程卡住。
        let box = OutputBox()
        let reader = DispatchQueue(label: "cc.yuntianyou.peek.tool-output")
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        if finished.wait(timeout: .now() + command.timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
            _ = readDone.wait(timeout: .now() + 2)
            return nil
        }
        readDone.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: box.data, as: UTF8.self)
    }
}
