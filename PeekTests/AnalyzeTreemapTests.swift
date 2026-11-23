import CoreGraphics
import XCTest
@testable import Peek

/// 方块视图的纯计算:squarified 布局、"其他"合并、条目分类和配色。
final class AnalyzeTreemapTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    // MARK: - 布局

    func testSquarifyFillsRectProportionally() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = TreemapLayout.squarify(values, in: rect)
        XCTAssertEqual(rects.count, values.count)

        let total = values.reduce(0, +)
        let area = Double(rect.width * rect.height)
        for (value, tile) in zip(values, rects) {
            // 面积和值成正比。
            XCTAssertEqual(Double(tile.width * tile.height), value / total * area, accuracy: 1)
            // 都在大矩形里。
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(tile), "\(tile)")
        }
        // 两两不重叠。
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01, "\(i) \(j)")
            }
        }
        // 铺满。
        let covered = rects.reduce(0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(covered, area, accuracy: 1)
    }

    func testSquarifyKeepsTilesReasonablySquare() {
        let rects = TreemapLayout.squarify(
            [10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
            in: CGRect(x: 0, y: 0, width: 800, height: 500))
        for tile in rects {
            let ratio = max(tile.width / tile.height, tile.height / tile.width)
            XCTAssertLessThan(ratio, 4, "\(tile)")
        }
    }

    func testSquarifyEdgeCases() {
        XCTAssertTrue(TreemapLayout.squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        // 空矩形、全零:每个值都给空矩形。
        XCTAssertEqual(TreemapLayout.squarify([1, 2], in: .zero), [.zero, .zero])
        XCTAssertEqual(
            TreemapLayout.squarify([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)),
            [.zero, .zero])
        // 只有一个值:铺满。
        let single = TreemapLayout.squarify([5], in: CGRect(x: 2, y: 3, width: 40, height: 20))
        XCTAssertEqual(single, [CGRect(x: 2, y: 3, width: 40, height: 20)])
        // 夹着 0 的值不占地方。
        let mixed = TreemapLayout.squarify([3, 0, 1], in: CGRect(x: 0, y: 0, width: 40, height: 10))
        XCTAssertEqual(mixed[1], .zero)
        XCTAssertEqual(Double(mixed[0].width * mixed[0].height), 300, accuracy: 0.5)
    }

    // MARK: - 合并成"其他"

    func testIndividualCountMergesTinyItems() {
        // 1000 + 10 个 1:每个 1 都不到 0.2%,合并成"其他"。
        let sizes: [UInt64] = [1000] + Array(repeating: 1, count: 10)
        XCTAssertEqual(TreemapLayout.individualCount(sizes: sizes), 1)
    }

    func testIndividualCountCapsTileNumber() {
        let sizes = Array(repeating: UInt64(100), count: 200)
        // 79 块单独 + 1 块"其他" = 80。
        XCTAssertEqual(TreemapLayout.individualCount(sizes: sizes), 79)
        // 不超过上限时全部单独成块。
        XCTAssertEqual(TreemapLayout.individualCount(sizes: Array(sizes.prefix(80))), 80)
    }

    func testIndividualCountDoesNotMergeSingleLeftover() {
        // 只剩 1 项要合并时直接单独画。
        XCTAssertEqual(TreemapLayout.individualCount(sizes: [1000, 1]), 2)
        // 超过上限时要留 2 项给"其他",不会出现只合并 1 项的"其他"。
        XCTAssertEqual(TreemapLayout.individualCount(sizes: Array(repeating: 5, count: 81)), 79)
    }

    func testIndividualCountIgnoresZeroSizes() {
        XCTAssertEqual(TreemapLayout.individualCount(sizes: []), 0)
        XCTAssertEqual(TreemapLayout.individualCount(sizes: [0, 0]), 0)
        XCTAssertEqual(TreemapLayout.individualCount(sizes: [50, 40, 0, 0]), 2)
    }

    // MARK: - Agent 识别

    func testAgentMatchesDirectoryAndDescendants() {
        XCTAssertEqual(agent(".claude")?.id, "claude")
        XCTAssertEqual(agent(".claude/projects")?.id, "claude")
        XCTAssertEqual(agent("Library/Application Support/Claude")?.id, "claude")
        XCTAssertEqual(agent(".codex")?.id, "codex")
        XCTAssertEqual(agent("Library/Caches/Codex")?.id, "codex")
        XCTAssertEqual(agent(".local/share/opencode")?.id, "opencode")
        XCTAssertEqual(agent(".ollama")?.id, "ollama")
        XCTAssertEqual(agent(".cache/huggingface/hub")?.id, "huggingface")
    }

    func testAgentDoesNotMatchParentsOrLookalikes() {
        // 上级目录(里面装着 Agent 目录)不算。
        XCTAssertNil(agent(".local"))
        XCTAssertNil(agent(".local/share"))
        XCTAssertNil(agent("Library/Application Support"))
        // 名字前缀一样但不是同一个目录。
        XCTAssertNil(agent(".claude-backup"))
        XCTAssertNil(agent(".codexrc"))
        // 主目录本身、主目录外面。
        XCTAssertNil(AnalyzeClassifier.agent(for: home, home: home))
        XCTAssertNil(AnalyzeClassifier.agent(for: URL(fileURLWithPath: "/tmp/.claude"), home: home))
    }

    func testAgentIdsAreUnique() {
        let ids = AnalyzeClassifier.agents.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - 类型

    func testCategoryRules() {
        XCTAssertEqual(category(".claude"), .agent)
        XCTAssertEqual(category("Applications"), .apps)
        XCTAssertEqual(
            AnalyzeClassifier.category(
                for: URL(fileURLWithPath: "/Applications/Safari.app"), isDirectory: true, home: home),
            .apps)
        XCTAssertEqual(category("work"), .developer)
        XCTAssertEqual(category("work/peek/node_modules"), .developer)
        XCTAssertEqual(category(".npm"), .developer)
        XCTAssertEqual(category("Library/Developer"), .developer)
        XCTAssertEqual(category("Movies"), .media)
        XCTAssertEqual(category("Pictures/Photos Library.photoslibrary"), .media)
        XCTAssertEqual(category("clip.mov", isDirectory: false), .media)
        XCTAssertEqual(category("Documents"), .documents)
        XCTAssertEqual(category("Downloads"), .documents)
        XCTAssertEqual(category("report.pdf", isDirectory: false), .documents)
        XCTAssertEqual(category("Library"), .system)
        XCTAssertEqual(category("Library/Caches"), .system)
        XCTAssertEqual(
            AnalyzeClassifier.category(for: URL(fileURLWithPath: "/System"), isDirectory: true, home: home),
            .system)
        XCTAssertEqual(category("random-folder"), .other)
        XCTAssertEqual(category("notes.bin", isDirectory: false), .other)
    }

    // MARK: - 配色

    func testColorMix() {
        XCTAssertEqual(AnalyzeTreemapColors.mix(0xFFFFFF, 0x000000, 1), 0xFFFFFF)
        XCTAssertEqual(AnalyzeTreemapColors.mix(0xFFFFFF, 0x000000, 0), 0x000000)
        XCTAssertEqual(AnalyzeTreemapColors.mix(0xFF0000, 0x0000FF, 0.5), 0x800080)
    }

    // MARK: - Agent 页

    func testAgentVirtualURLs() {
        let claude = AnalyzeClassifier.agents.first { $0.id == "claude" }!
        let url = AnalyzeAgentScan.url(for: claude)
        XCTAssertEqual(AnalyzeAgentScan.agentID(from: url), "claude")
        XCTAssertNil(AnalyzeAgentScan.agentID(from: AnalyzeAgentScan.rootURL))
        XCTAssertNil(AnalyzeAgentScan.agentID(from: home.appendingPathComponent(".claude")))
        // 虚拟条目也能认出 Agent、归到 Agent 类。
        XCTAssertEqual(AnalyzeClassifier.agent(for: url, home: home)?.id, "claude")
        XCTAssertEqual(AnalyzeClassifier.category(for: url, isDirectory: true, home: home), .agent)
    }

    func testAgentScanSumsEachAgentsDirectories() throws {
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-agent-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fake) }
        func write(_ relative: String, bytes: Int) throws {
            let url = fake.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: url)
        }
        try write(".claude/projects/a.jsonl", bytes: 300_000)
        try write("Library/Caches/Claude/blob", bytes: 100_000)
        try write(".codex/sessions/s.jsonl", bytes: 50_000)
        try write(".local/share/other/x", bytes: 900_000)  // 不是 Agent
        try FileManager.default.createDirectory(
            at: fake.appendingPathComponent(".gemini"), withIntermediateDirectories: true)  // 空目录

        let result = AnalyzeAgentScan.scan(home: fake)
        XCTAssertFalse(result.wasCancelled)
        // 只有 Claude 和 Codex;空的 Gemini、不是 Agent 的目录都不列。
        XCTAssertEqual(result.agents.map(\.name), ["Claude Code", "Codex"])
        let claudePaths = try XCTUnwrap(result.paths["claude"])
        XCTAssertEqual(claudePaths.map(\.name), ["~/.claude", "~/Library/Caches/Claude"])
        XCTAssertEqual(result.agents[0].size, claudePaths.reduce(0) { $0 + $1.size })
        XCTAssertGreaterThanOrEqual(result.agents[0].size, 400_000)
        XCTAssertNil(result.paths["gemini"])
    }

    func testScanReportsGrowingPartialItems() throws {
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-partial-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fake) }
        for dir in ["a", "b"] {
            let folder = fake.appendingPathComponent(dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<400 {
                try Data(repeating: 1, count: 8_192).write(to: folder.appendingPathComponent("\(index)"))
            }
        }

        final class Collector: @unchecked Sendable {
            let lock = NSLock()
            var snapshots: [[AnalyzeItem]] = []
        }
        let collector = Collector()
        let result = AnalyzeScanner.scan(root: fake, progress: { value in
            guard let items = value.items else { return }
            collector.lock.lock()
            collector.snapshots.append(items)
            collector.lock.unlock()
        })
        let final = Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0.size) })
        XCTAssertFalse(collector.snapshots.isEmpty)
        for snapshot in collector.snapshots {
            // 中途大小不会超过最终大小，名字也不会重复。
            XCTAssertEqual(Set(snapshot.map(\.name)).count, snapshot.count)
            for item in snapshot {
                XCTAssertLessThanOrEqual(item.size, final[item.name] ?? 0, item.name)
            }
        }
    }

    func testPauseGateStopsScan() {
        let gate = AnalyzePauseGate()
        XCTAssertFalse(gate.shouldStop())
        gate.requestStop()
        XCTAssertTrue(gate.shouldStop())
    }

    /// 造一棵树:a/(30 个文件)、b/x/(30 个)、b/y/(30 个)、c/(30 个)、d.bin。
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-resume-\(UUID().uuidString)", isDirectory: true)
        for dir in ["a", "b/x", "b/y", "c"] {
            let folder = root.appendingPathComponent(dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<30 {
                try Data(repeating: 1, count: 4_096 * (index % 3 + 1))
                    .write(to: folder.appendingPathComponent("\(index)"))
            }
        }
        try Data(repeating: 2, count: 50_000).write(to: root.appendingPathComponent("d.bin"))
        return root
    }

    /// 在第 n 次检查时停下,再从检查点接着扫,一直到扫完;结果要和一口气扫完一样。
    func testResumeFromCheckpointMatchesFullScan() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let full = AnalyzeScanner.scan(root: root)
        XCTAssertFalse(full.wasCancelled)
        let expected = Dictionary(uniqueKeysWithValues: full.items.map { ($0.name, $0.size) })

        // 列一个目录本身不能拆开停（停下后这个目录重列），所以每次至少要能从根一路列到最深最大的目录(5 + 2 + 30 项)。
        for stopAfter in [40, 55, 70, 100, 140] {
            var checkpoint: AnalyzeScanCheckpoint?
            var result = AnalyzeScanResult()
            var rounds = 0
            repeat {
                final class Counter: @unchecked Sendable { var value = 0 }
                let counter = Counter()
                result = AnalyzeScanner.scan(root: root, resume: checkpoint, isCancelled: {
                    counter.value += 1
                    return counter.value > stopAfter
                })
                if result.wasCancelled {
                    checkpoint = try XCTUnwrap(result.checkpoint, "stopAfter \(stopAfter)")
                }
                rounds += 1
            } while result.wasCancelled && rounds < 200
            XCTAssertFalse(result.wasCancelled, "stopAfter \(stopAfter)")
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: result.items.map { ($0.name, $0.size) }), expected,
                "stopAfter \(stopAfter)")
            XCTAssertEqual(result.totalBytes, full.totalBytes, "stopAfter \(stopAfter)")
        }
    }

    func testCheckpointRoundTripsThroughJSON() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let partial = AnalyzeScanner.scan(root: root, isCancelled: {
            counter.value += 1
            return counter.value > 50
        })
        let checkpoint = try XCTUnwrap(partial.checkpoint)
        XCTAssertFalse(checkpoint.frames.isEmpty)
        let decoded = try JSONDecoder().decode(
            AnalyzeScanCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        XCTAssertEqual(decoded, checkpoint)
        let resumed = AnalyzeScanner.scan(root: root, resume: decoded)
        XCTAssertEqual(resumed.totalBytes, AnalyzeScanner.scan(root: root).totalBytes)
    }

    func testAgentScanResumesFromCheckpoint() throws {
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-agent-resume-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fake) }
        for (dir, count) in [(".claude/projects", 40), ("Library/Caches/Claude", 10), (".codex/sessions", 25)] {
            let folder = fake.appendingPathComponent(dir, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<count {
                try Data(repeating: 3, count: 8_192).write(to: folder.appendingPathComponent("\(index)"))
            }
        }
        let full = AnalyzeAgentScan.scan(home: fake)
        for stopAfter in [45, 60, 90] {
            var checkpoint: AnalyzeAgentScan.Checkpoint?
            var result = AnalyzeAgentScan.Result()
            var rounds = 0
            repeat {
                final class Counter: @unchecked Sendable { var value = 0 }
                let counter = Counter()
                result = AnalyzeAgentScan.scan(home: fake, resume: checkpoint, isCancelled: {
                    counter.value += 1
                    return counter.value > stopAfter
                })
                checkpoint = result.checkpoint
                rounds += 1
            } while result.wasCancelled && rounds < 200
            XCTAssertFalse(result.wasCancelled)
            XCTAssertEqual(result.agents.map(\.name), full.agents.map(\.name), "stopAfter \(stopAfter)")
            XCTAssertEqual(result.agents.map(\.size), full.agents.map(\.size), "stopAfter \(stopAfter)")
            XCTAssertEqual(result.paths, full.paths, "stopAfter \(stopAfter)")
        }
    }

    func testAgentScanHonoursCancellation() {
        let result = AnalyzeAgentScan.scan(home: home, isCancelled: { true })
        XCTAssertTrue(result.agents.isEmpty)
    }

    // MARK: - 辅助

    private func agent(_ relative: String) -> AnalyzeAgent? {
        AnalyzeClassifier.agent(for: home.appendingPathComponent(relative), home: home)
    }

    private func category(_ relative: String, isDirectory: Bool = true) -> AnalyzeCategory {
        AnalyzeClassifier.category(
            for: home.appendingPathComponent(relative), isDirectory: isDirectory, home: home)
    }
}
