import CoreGraphics
import XCTest
@testable import Peek

/// 公共方块组件里"画图标 / 画文字 / 都画"的纯计算。
final class TreemapTileLayoutTests: XCTestCase {

    // MARK: - 没有图标时和旧行为一致

    func testWithoutIconOnlyTextFitsRuleApplies() {
        // 旧规则:宽 ≥ 44、高 ≥ 28 才写字,没有只画图标这一档。
        let sizes: [(CGFloat, CGFloat)] = [
            (0, 0), (23, 100), (44, 27), (43, 28), (44, 28), (60, 84),
            (179, 109), (180, 110), (400, 300),
        ]
        for (width, height) in sizes {
            let mode = TreemapTileLayoutMode.mode(width: width, height: height, hasIcon: false)
            let textFits = width >= 44 && height >= 28
            XCTAssertEqual(mode.showsText, textFits, "\(width)×\(height)")
            XCTAssertFalse(mode.showsIcon, "\(width)×\(height)")
            XCTAssertEqual(mode, textFits ? .textOnly : .none, "\(width)×\(height)")
        }
    }

    // MARK: - 图标 + 文字

    func testIconAndTextNeedsSixtyByEightyFour() {
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 60, height: 84, hasIcon: true),
            .iconAndText(iconSize: 32))
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 59, height: 84, hasIcon: true),
            .textOnly)
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 60, height: 83, hasIcon: true),
            .textOnly)
    }

    func testLargeTileGetsBiggerIcon() {
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 180, height: 110, hasIcon: true),
            .iconAndText(iconSize: 40))
        // 差一点就还是 32。
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 179, height: 110, hasIcon: true),
            .iconAndText(iconSize: 32))
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 180, height: 109, hasIcon: true),
            .iconAndText(iconSize: 32))
    }

    // MARK: - 放不下图标 + 文字的退化

    func testFallsBackToTextWhenIconAndTextDoNotFitButTextDoes() {
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 44, height: 28, hasIcon: true), .textOnly)
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 44, height: 84, hasIcon: true), .textOnly)
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 60, height: 28, hasIcon: true), .textOnly)
    }

    func testFallsBackToIconOnlyWhenTextDoesNotFit() {
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 43, height: 27, hasIcon: true),
            .iconOnly(iconSize: 20))
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 24, height: 24, hasIcon: true),
            .iconOnly(iconSize: 20))
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 30, height: 200, hasIcon: true),
            .iconOnly(iconSize: 20))
        // 再小就只留色块。
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 23, height: 24, hasIcon: true), .none)
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 24, height: 23, hasIcon: true), .none)
        XCTAssertEqual(
            TreemapTileLayoutMode.mode(width: 0, height: 0, hasIcon: true), .none)
    }

    // MARK: - 常量

    func testIconSizesAndSpacingMatchSpec() {
        XCTAssertEqual(TreemapTileLayoutMode.iconSize, 32)
        XCTAssertEqual(TreemapTileLayoutMode.largeIconSize, 40)
        XCTAssertEqual(TreemapTileLayoutMode.iconOnlySize, 20)
        XCTAssertEqual(TreemapTileLayoutMode.iconTextSpacing, 4)
        // 四档模式里只有画图标的模式给图标大小。
        XCTAssertNil(TreemapTileLayoutMode.none.iconSize)
        XCTAssertNil(TreemapTileLayoutMode.textOnly.iconSize)
        XCTAssertEqual(TreemapTileLayoutMode.iconOnly(iconSize: 20).iconSize, 20)
        XCTAssertEqual(TreemapTileLayoutMode.iconAndText(iconSize: 40).iconSize, 40)
    }
}