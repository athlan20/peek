import XCTest

@testable import Peek

/// PEEK-18 面板电池行、高占用进程、累计记录用到的纯计算和 `HistoryTotals` 的持久化。
@MainActor
final class PanelExtraTests: XCTestCase {
    // MARK: - HistoryTotals.adding

    func testAddingCleanAddsFreedBytes() {
        let totals = HistoryTotals(cleanedBytes: 100, uninstalledCount: 1, optimizedCount: 2)
            .adding(HistoryEntry(kind: .clean, itemCount: 5, freedBytes: 900, failedCount: 2))
        XCTAssertEqual(
            totals, HistoryTotals(cleanedBytes: 1_000, uninstalledCount: 1, optimizedCount: 2))
    }

    func testAddingUninstallAndOptimizeCountOncePerRecord() {
        let totals = HistoryTotals()
            .adding(HistoryEntry(kind: .uninstall, itemCount: 7, freedBytes: 4_096, failedCount: 2))
            .adding(HistoryEntry(kind: .optimize, itemCount: 3, freedBytes: 10, failedCount: 4))
            .adding(HistoryEntry(kind: .optimize, itemCount: 1))
        XCTAssertEqual(
            totals, HistoryTotals(cleanedBytes: 0, uninstalledCount: 1, optimizedCount: 2))
    }

    func testSeedFromEntries() {
        let entries = [
            HistoryEntry(kind: .clean, itemCount: 3, freedBytes: 2_048),
            HistoryEntry(kind: .uninstall, itemCount: 4, failedCount: 1),
            HistoryEntry(kind: .optimize, itemCount: 5),
            HistoryEntry(kind: .clean, itemCount: 1, freedBytes: 1_024),
        ]
        XCTAssertEqual(
            HistoryTotals.seed(from: entries),
            HistoryTotals(cleanedBytes: 3_072, uninstalledCount: 1, optimizedCount: 1))
        XCTAssertEqual(HistoryTotals.seed(from: []), HistoryTotals())
    }

    // MARK: - 累计计数文件

    func testTotalsSeededFromExistingHistory() throws {
        let directory = try makeTempDirectory()
        let historyURL = directory.appendingPathComponent("history.json")
        try writeHistoryFile(
            [
                HistoryEntry(kind: .clean, itemCount: 3, freedBytes: 2_048),
                HistoryEntry(kind: .clean, itemCount: 1, freedBytes: 1_024),
                HistoryEntry(kind: .uninstall, itemCount: 6, failedCount: 1),
            ], to: historyURL)

        let store = HistoryStore(fileURL: historyURL)
        let expected = HistoryTotals(
            cleanedBytes: 3_072, uninstalledCount: 1, optimizedCount: 0)
        XCTAssertEqual(store.totals, expected)
        // 一次性初始化后立刻写盘，下次启动直接读文件。
        XCTAssertEqual(HistoryStore.readTotals(at: store.totalsFileURL), .loaded(expected))
        XCTAssertEqual(
            store.totalsFileURL.lastPathComponent, HistoryStore.totalsFileName)
        XCTAssertEqual(store.totalsFileURL.deletingLastPathComponent(), directory)
    }

    func testTotalsRoundTripAfterRecord() async throws {
        let directory = try makeTempDirectory()
        let historyURL = directory.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: historyURL)
        XCTAssertEqual(store.totals, HistoryTotals())

        store.record(HistoryEntry(kind: .clean, itemCount: 2, freedBytes: 5_000))
        store.record(HistoryEntry(kind: .uninstall, itemCount: 3, failedCount: 1))
        let expected = HistoryTotals(cleanedBytes: 5_000, uninstalledCount: 1, optimizedCount: 0)
        XCTAssertEqual(store.totals, expected)

        // 写盘在后台队列，等文件跟上。
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if HistoryStore.readTotals(at: store.totalsFileURL) == .loaded(expected) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(HistoryStore.readTotals(at: store.totalsFileURL), .loaded(expected))

        // 重新打开（模拟下次启动）读到的是同一个累计值。
        let reopened = HistoryStore(fileURL: historyURL)
        XCTAssertEqual(reopened.totals, expected)
    }

    func testCorruptTotalsFallBackToHistorySeed() throws {
        let directory = try makeTempDirectory()
        let historyURL = directory.appendingPathComponent("history.json")
        try writeHistoryFile(
            [HistoryEntry(kind: .optimize, itemCount: 4)], to: historyURL)

        let totalsURL = HistoryStore.totalsURL(for: historyURL)
        try Data("not json".utf8).write(to: totalsURL)
        XCTAssertEqual(HistoryStore.readTotals(at: totalsURL), .corrupt)

        let store = HistoryStore(fileURL: historyURL)
        XCTAssertEqual(store.totals.optimizedCount, 1)
        XCTAssertEqual(
            HistoryStore.readTotals(at: totalsURL),
            .loaded(HistoryTotals(cleanedBytes: 0, uninstalledCount: 0, optimizedCount: 1)))
    }

    // MARK: - 电池

    func testBatteryAlertOnlyWhenLowAndNotCharging() {
        XCTAssertTrue(PanelFormat.batteryIsAlert(level: 0.19, isCharging: false))
        XCTAssertTrue(PanelFormat.batteryIsAlert(level: 0, isCharging: false))
        // 正好 20% 不算告警。
        XCTAssertFalse(PanelFormat.batteryIsAlert(level: 0.2, isCharging: false))
        // 充电中再低也不用强调色。
        XCTAssertFalse(PanelFormat.batteryIsAlert(level: 0.05, isCharging: true))
    }

    func testBatteryDetailTextIsLocalized() {
        // 英文是源语言，测试包里没有本地化资源，查不到时返回的就是插值后的英文原文。
        let sourceBundle = Bundle(for: PanelExtraTests.self)
        let charging = BatteryStats(level: 0.82, isCharging: true, health: 1.0, cycleCount: 312)
        XCTAssertEqual(
            PanelFormat.batteryDetailText(charging, bundle: sourceBundle),
            "Charging · Health 100% · 312 cycles")
        XCTAssertEqual(
            PanelFormat.batteryDetailText(
                charging, locale: Locale(identifier: "zh-Hans"), bundle: .main),
            "充电中 · 健康度 100% · 312 次循环")

        // 读不到健康度、循环次数就省略那两段。
        let unknown = BatteryStats(level: 0.5, isCharging: false, health: nil, cycleCount: nil)
        XCTAssertEqual(PanelFormat.batteryDetailText(unknown, bundle: sourceBundle), "On battery")
        XCTAssertEqual(
            PanelFormat.batteryDetailText(
                unknown, locale: Locale(identifier: "zh-Hans"), bundle: .main),
            "使用电池")
    }

    // MARK: - 高占用进程

    func testTopProcessesSortsByCPUAndKeepsThree() {
        let processes = [
            ProcessUsage(pid: 1, name: "slow", cpu: 0.1, memoryBytes: 900),
            ProcessUsage(pid: 2, name: "busy", cpu: 2.5, memoryBytes: 10),
            ProcessUsage(pid: 3, name: "mid", cpu: 0.7, memoryBytes: 100),
            ProcessUsage(pid: 4, name: "mid-heavy", cpu: 0.7, memoryBytes: 200),
            ProcessUsage(pid: 5, name: "hot", cpu: 1.2, memoryBytes: 50),
        ]
        // CPU 降序；CPU 相同时内存多的在前。
        XCTAssertEqual(PanelFormat.topProcesses(processes).map(\.pid), [2, 5, 4])
        XCTAssertEqual(PanelFormat.topProcesses(processes, limit: 2).map(\.pid), [2, 5])
        XCTAssertTrue(PanelFormat.topProcesses([]).isEmpty)
    }

    func testCPUPercentUsesFractionOfOneCore() {
        XCTAssertEqual(PanelFormat.cpuPercent(1), "100%")
        // 多线程可以超过 100%。
        XCTAssertEqual(PanelFormat.cpuPercent(2.5), "250%")
        XCTAssertEqual(PanelFormat.cpuPercent(0.004), "0%")
        XCTAssertEqual(PanelFormat.cpuPercent(-1), "0%")
    }

    // MARK: - 辅助

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "peek-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// 按 `history.json` 的格式写一份历史文件（seed 测试的输入）。
    private func writeHistoryFile(_ entries: [HistoryEntry], to url: URL) throws {
        struct FileContents: Encodable {
            var version: Int
            var entries: [HistoryEntry]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            FileContents(version: HistoryFileFormat.version, entries: entries))
        try data.write(to: url)
    }
}