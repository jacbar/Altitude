import XCTest

final class SwipeGestureTests: XCTestCase {
    func testEndPastThresholdCommitsDirection() {
        var state = SwipeGestureState()
        let now = Date()
        XCTAssertNil(
            state.consume(
                SwipeSample(progress: 0.12, direction: .right, began: true, ended: false),
                now: now
            )
        )
        let committed = state.consume(
            SwipeSample(progress: 0.12, direction: .right, began: false, ended: true),
            now: now.addingTimeInterval(0.1)
        )
        XCTAssertEqual(committed, .right)
        XCTAssertFalse(state.swallowingSwipe)
    }

    func testEndBelowThresholdCancels() {
        var state = SwipeGestureState()
        let now = Date()
        _ = state.consume(
            SwipeSample(progress: 0.05, direction: .left, began: true, ended: false),
            now: now
        )
        let committed = state.consume(
            SwipeSample(progress: 0.05, direction: .left, began: false, ended: true),
            now: now.addingTimeInterval(0.1)
        )
        XCTAssertNil(committed)
        XCTAssertFalse(state.swallowingSwipe)
    }

    func testReversePeakCommitsFinalDirection() {
        var state = SwipeGestureState()
        let now = Date()
        _ = state.consume(
            SwipeSample(progress: 0.1, direction: .right, began: true, ended: false),
            now: now
        )
        _ = state.consume(
            SwipeSample(progress: -0.2, direction: .left, began: false, ended: false),
            now: now.addingTimeInterval(0.05)
        )
        let committed = state.consume(
            SwipeSample(progress: -0.2, direction: .left, began: false, ended: true),
            now: now.addingTimeInterval(0.1)
        )
        XCTAssertEqual(committed, .left)
    }

    func testExpireIfStuckClearsSwallowing() {
        var state = SwipeGestureState()
        let now = Date()
        _ = state.consume(
            SwipeSample(progress: 0.1, direction: .right, began: true, ended: false),
            now: now
        )
        XCTAssertTrue(state.swallowingSwipe)
        XCTAssertTrue(state.expireIfStuck(now: now.addingTimeInterval(1.51)))
        XCTAssertFalse(state.swallowingSwipe)
        XCTAssertEqual(state.swipePeak, 0)
        XCTAssertNil(state.swipeDirection)
    }
}
