import XCTest
@testable import Peek

/// 卸载窗口量大小能不能暂停。真实的磁盘测量不在这里测,只测和磁盘无关的暂停状态机。
final class UninstallMeasureStateTests: XCTestCase {

    func testNothingPendingCannotBePaused() {
        var state = UninstallMeasureState()
        XCTAssertFalse(state.isPaused)
        XCTAssertFalse(UninstallMeasureState.canPause(pendingCount: 0))
        state.toggle(pendingCount: 0)
        XCTAssertFalse(state.isPaused)
    }

    func testTogglePausesAndResumesWhileAppsArePending() {
        var state = UninstallMeasureState()
        XCTAssertTrue(UninstallMeasureState.canPause(pendingCount: 3))
        state.toggle(pendingCount: 3)
        XCTAssertTrue(state.isPaused)
        // 暂停后还没量完,可以继续。
        state.toggle(pendingCount: 2)
        XCTAssertFalse(state.isPaused)
    }

    func testResumeClearsPauseLikeReload() {
        // `UninstallModel.reload()` 就是用 `resume()` 清暂停的。
        var state = UninstallMeasureState()
        state.toggle(pendingCount: 5)
        XCTAssertTrue(state.isPaused)
        state.resume()
        XCTAssertFalse(state.isPaused)
    }
}

/// 没有 App 时 `UninstallModel` 不碰磁盘的可见状态。
@MainActor
final class UninstallModelPauseTests: XCTestCase {

    func testNewModelIsNotMeasuringAndCannotPause() {
        let model = UninstallModel()
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertFalse(model.isMeasuring)
        XCTAssertFalse(model.isPaused)
        // 没有 App 没量完,togglePause 什么也不做。
        model.togglePause()
        XCTAssertFalse(model.isPaused)
    }
}