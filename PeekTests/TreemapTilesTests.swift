import AppKit
import SwiftUI
import XCTest
@testable import Peek

/// 公共方块组件的纯计算:条目 → 方块(过滤、排序、"其他"合并)。
final class TreemapTilesTests: XCTestCase {
    private let blue = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6)

    // MARK: - 过滤和排序

    func testZeroSizeEntriesAreNotDrawn() {
        let tiles = TreemapTiles.make(
            entries: [entry("a", size: 100), entry("zero", size: 0), entry("b", size: 50)],
            otherTitle: "Other",
            otherSubtitle: itemsText)
        XCTAssertEqual(tiles.map(\.title), ["a", "b"])
        // 调用方另列大小为 0 的条目，组件里不画。
        XCTAssertFalse(tiles.contains { $0.size == 0 })
    }

    func testTilesAreSortedBySizeDescending() {
        let tiles = TreemapTiles.make(
            entries: [entry("s", size: 10), entry("l", size: 900), entry("m", size: 200)],
            otherTitle: "Other",
            otherSubtitle: itemsText)
        XCTAssertEqual(tiles.map(\.title), ["l", "m", "s"])
        XCTAssertEqual(tiles.map(\.size), [900, 200, 10])
    }

    func testEmptyInputDrawsNothing() {
        XCTAssertTrue(TreemapTiles.make(entries: [], otherTitle: "Other", otherSubtitle: itemsText).isEmpty)
        XCTAssertTrue(
            TreemapTiles.make(
                entries: [entry("zero", size: 0)], otherTitle: "Other", otherSubtitle: itemsText).isEmpty)
    }

    // MARK: - 合并成"其他"

    func testTinyEntriesAreMergedIntoOther() {
        let entries = [entry("big", size: 1000)] + (0..<10).map { entry("tiny\($0)", size: 1) }
        let tiles = TreemapTiles.make(entries: entries, otherTitle: "Other", otherSubtitle: itemsText)
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].title, "big")
        let other = tiles[1]
        XCTAssertNil(other.entry)
        XCTAssertEqual(other.title, "Other")
        XCTAssertEqual(other.subtitle, "10 items")
        XCTAssertEqual(other.members.map(\.title), (0..<10).map { "tiny\($0)" })
        XCTAssertEqual(other.size, 10)
        XCTAssertEqual(other.color, TreemapTiles.otherColor)
    }

    func testTileCountIsCapped() {
        let entries = (0..<200).map { entry("item\($0)", size: 100) }
        let tiles = TreemapTiles.make(entries: entries, otherTitle: "Other", otherSubtitle: itemsText)
        // 79 块单独 + 1 块"其他" = 80。
        XCTAssertEqual(tiles.count, 80)
        XCTAssertEqual(tiles.last?.members.count, 121)
        XCTAssertEqual(tiles.last?.size, 121 * 100)
        XCTAssertEqual(tiles.dropLast().count, 79)
    }

    func testMinFractionZeroLeavesOnlyTheTileCap() {
        // 1000 + 20 个 1:默认 0.2% 会把小的全并进"其他",传 0 就各自成块。
        let entries = [entry("big", size: 1000)] + (0..<20).map { entry("tiny\($0)", size: 1) }
        let tiles = TreemapTiles.make(
            entries: entries, otherTitle: "Other", otherSubtitle: itemsText, minFraction: 0)
        XCTAssertEqual(tiles.count, 21)
        XCTAssertTrue(tiles.allSatisfy { $0.entry != nil })
        XCTAssertFalse(tiles.contains { $0.title == "Other" })
        // 数量上限还是 80:79 块单独 + 1 块"其他"。
        let many = (0..<200).map { entry("item\($0)", size: 100) }
        let capped = TreemapTiles.make(
            entries: many, otherTitle: "Other", otherSubtitle: itemsText, minFraction: 0)
        XCTAssertEqual(capped.count, 80)
        XCTAssertEqual(capped.last?.members.count, 121)
    }

    func testSingleLeftoverIsNotMerged() {
        let tiles = TreemapTiles.make(
            entries: [entry("big", size: 1000), entry("small", size: 1)],
            otherTitle: "Other",
            otherSubtitle: itemsText)
        XCTAssertEqual(tiles.map(\.title), ["big", "small"])
        XCTAssertTrue(tiles.allSatisfy { $0.entry != nil })
    }

    func testOtherSizeIsSumOfMembers() throws {
        // 1000 + 20 个 1:每个都不到 0.2%,全部并进"其他"。
        let entries = [entry("big", size: 1000)] + (0..<20).map { entry("tiny\($0)", size: 1) }
        let tiles = TreemapTiles.make(entries: entries, otherTitle: "别的", otherSubtitle: itemsText)
        let other = try XCTUnwrap(tiles.last)
        XCTAssertEqual(other.size, 20)
        XCTAssertEqual(other.members.count, 20)
        XCTAssertEqual(other.subtitle, "20 items")
        XCTAssertEqual(other.accessibilityLabel, "别的, \(TreemapText.size(20))")
        // "其他"的提示只有标题、副标题、大小。
        XCTAssertEqual(other.tooltip, "别的\n20 items\n\(TreemapText.size(20))")
    }

    // MARK: - 条目上的东西原样带到方块

    func testEntryFieldsAreCarriedToTiles() throws {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let marked = TreemapEntry(
            id: "id-1",
            title: "标题",
            subtitle: "副标题",
            size: 42,
            color: blue,
            isDimmed: true,
            badge: .lock,
            icon: icon,
            tooltip: "标题\n副标题\n42 bytes",
            accessibilityLabel: "标题, 42 bytes")
        let plain = entry("id-2", size: 8)
        let tiles = TreemapTiles.make(
            entries: [plain, marked], otherTitle: "Other", otherSubtitle: itemsText)
        // 两个都够大,都单独成块。
        let tile = try XCTUnwrap(tiles.first { $0.id == "id-1" })
        XCTAssertEqual(tile.entry, marked)
        XCTAssertEqual(tile.title, "标题")
        XCTAssertEqual(tile.subtitle, "副标题")
        XCTAssertEqual(tile.size, 42)
        XCTAssertEqual(tile.color, blue)
        XCTAssertEqual(tile.isDimmed, true)
        // `isDimmed` 的语义不变,等于明显变暗。
        XCTAssertEqual(tile.dimLevel, .strong)
        XCTAssertEqual(tile.badge, .lock)
        XCTAssertEqual(tile.icon, icon)
        XCTAssertEqual(tile.tooltip, "标题\n副标题\n42 bytes")
        XCTAssertEqual(tile.accessibilityLabel, "标题, 42 bytes")
        XCTAssertEqual(tile.members, [])
    }

    // MARK: - 辅助

    private func entry(_ title: String, size: UInt64) -> TreemapEntry {
        TreemapEntry(
            id: title,
            title: title,
            subtitle: nil,
            size: size,
            color: blue,
            tooltip: title,
            accessibilityLabel: title)
    }

    private func itemsText(_ count: Int) -> String { "\(count) items" }
}