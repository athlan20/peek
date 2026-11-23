import AppKit
import SwiftUI
import XCTest
@testable import Peek

/// 卸载方块视图的纯计算:最后使用 → 颜色档位、不能卸载 → 变暗 / 徽标、方块数据和悬停提示。
final class UninstallTreemapTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 辅助

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    private func app(
        name: String = "Shop",
        bundleID: String = "com.example.shop",
        bytes: UInt64? = 5_000_000,
        lastUsed: Date? = nil,
        blocked: UninstallBlockReason? = nil,
        isAppStore: Bool = false
    ) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app", isDirectory: true),
            name: name,
            bundleID: bundleID,
            version: "1.0",
            isAppStore: isAppStore,
            bytes: bytes,
            lastUsed: lastUsed,
            blocked: blocked)
    }

    // MARK: - 颜色档位

    func testBandsFollowLastUsed() {
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: nil, now: now), .unknown)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: now, now: now), .week)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(7), now: now), .week)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(7) - 1, now: now), .month)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(30), now: now), .month)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(30) - 1, now: now), .quarter)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(90), now: now), .quarter)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(90) - 1, now: now), .year)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(365), now: now), .year)
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: daysAgo(365) - 1, now: now), .older)
        // 时间比 now 还晚(Spotlight 数据不准)也算最近用过。
        XCTAssertEqual(UninstallTreemapColors.band(lastUsed: now.addingTimeInterval(60), now: now), .week)
    }

    func testEveryBandHasItsOwnColor() {
        XCTAssertEqual(UninstallTreemapColors.hex(.week), 0x3E5C8A)
        XCTAssertEqual(UninstallTreemapColors.hex(.month), 0x48685F)
        XCTAssertEqual(UninstallTreemapColors.hex(.quarter), 0x6B6A3E)
        XCTAssertEqual(UninstallTreemapColors.hex(.year), 0x7E5F36)
        XCTAssertEqual(UninstallTreemapColors.hex(.older), 0x7A4A32)
        XCTAssertEqual(UninstallTreemapColors.hex(.unknown), 0x4A4F5C)
        XCTAssertEqual(Set(UninstallUsageBand.allCases.map(UninstallTreemapColors.hex)).count, 6)
    }

    // MARK: - 不能卸载的显示方式

    func testBlockReasonMapsToDimAndBadge() {
        XCTAssertEqual(UninstallTreemap.state(for: nil), .available)
        XCTAssertEqual(UninstallTreemap.state(for: .running), .running)
        for reason: UninstallBlockReason in [.systemApp, .peekItself, .appleApp, .vendorManaged] {
            XCTAssertEqual(UninstallTreemap.state(for: reason), .locked)
        }
        // 正在运行只是轻微变暗,不是一片黑;其他原因明显变暗并带锁。
        XCTAssertEqual(UninstallTreemap.State.available.dimLevel, TreemapDim.none)
        XCTAssertEqual(UninstallTreemap.State.available.badge, nil)
        XCTAssertEqual(UninstallTreemap.State.running.dimLevel, .light)
        XCTAssertEqual(UninstallTreemap.State.running.badge, .running)
        XCTAssertEqual(UninstallTreemap.State.locked.dimLevel, .strong)
        XCTAssertEqual(UninstallTreemap.State.locked.badge, .lock)
        XCTAssertLessThan(
            TreemapDim.light.overlayOpacity, TreemapDim.strong.overlayOpacity)
    }

    // MARK: - 方块数据

    func testUnmeasuredAppsAreNotDrawn() {
        let apps = [
            app(name: "Measured", bundleID: "com.a", bytes: 1000),
            app(name: "Waiting", bundleID: "com.b", bytes: nil),
            app(name: "Empty", bundleID: "com.c", bytes: 0),
        ]
        let entries = UninstallTreemap.entries(apps: apps, now: now)
        XCTAssertEqual(entries.map(\.title), ["Measured"])
        XCTAssertEqual(entries[0].id, apps[0].url.path)
        XCTAssertEqual(entries[0].size, 1000)
        XCTAssertNil(UninstallTreemap.entry(for: apps[1], now: now))
    }

    func testEntryCarriesBandColorSizeAndBlockState() throws {
        let entry = try XCTUnwrap(UninstallTreemap.entry(
            for: app(bytes: 2_000_000, lastUsed: daysAgo(10), blocked: .running), now: now))
        XCTAssertEqual(entry.color, UninstallTreemapColors.color(.month))
        XCTAssertEqual(entry.size, 2_000_000)
        XCTAssertNil(entry.subtitle)
        XCTAssertEqual(entry.dimLevel, .light)
        XCTAssertEqual(entry.badge, .running)
        // 图标由视图补,纯数据里没有。
        XCTAssertNil(entry.icon)

        let locked = UninstallTreemap.entry(
            for: app(name: "Safari", bundleID: "com.apple.Safari", blocked: .appleApp), now: now)
        XCTAssertEqual(locked?.dimLevel, .strong)
        XCTAssertEqual(locked?.badge, .lock)
    }

    func testTooltipHasWhatTheTileCannotShow() throws {
        let entry = try XCTUnwrap(UninstallTreemap.entry(
            for: app(
                bundleID: "com.example.shop", bytes: 5_000_000,
                lastUsed: daysAgo(3), blocked: .running, isAppStore: true),
            now: now))
        let tooltip = entry.tooltip
        XCTAssertTrue(tooltip.contains("com.example.shop"), tooltip)
        XCTAssertTrue(tooltip.contains(UninstallBlockReason.running.explanation), tooltip)
        XCTAssertTrue(tooltip.contains(TreemapText.size(5_000_000)), tooltip)
        XCTAssertTrue(tooltip.contains("Shop"), tooltip)
        XCTAssertGreaterThan(tooltip.split(separator: "\n").count, 4)
        // 方块上不写 Bundle ID。
        XCTAssertNil(entry.subtitle)

        let unused = try XCTUnwrap(UninstallTreemap.entry(for: app(lastUsed: nil), now: now))
        XCTAssertTrue(unused.tooltip.contains(String(localized: "No record")), unused.tooltip)
        XCTAssertFalse(unused.tooltip.contains(String(localized: "From the App Store")), unused.tooltip)
    }

    func testSmallAppIsKeptWhenOnlyTileCountCaps() {
        // 一个 2 GB 加 60 个 5 MB 左右:占比都不到 0.2%,卸载传 minFraction = 0 后各自成块。
        var apps = [app(name: "Big", bundleID: "com.big", bytes: 2_000_000_000)]
        apps += (0..<60).map { app(name: "Small\($0)", bundleID: "com.small.\($0)", bytes: 5_000_000) }
        let entries = UninstallTreemap.entries(apps: apps, now: now)
        let tiles = TreemapTiles.make(
            entries: entries, otherTitle: "Other", otherSubtitle: { "\($0) items" }, minFraction: 0)
        XCTAssertEqual(tiles.count, 61)
        XCTAssertTrue(tiles.contains { $0.title == "Small59" })
        XCTAssertTrue(tiles.allSatisfy { $0.entry != nil })
    }
}