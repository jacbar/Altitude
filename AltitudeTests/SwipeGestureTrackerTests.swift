import XCTest

final class SwipeGestureTrackerTests: XCTestCase {
    func testReversedSwipeDoesNotHop() {
        var tracker = SwipeGestureTracker()
        let now = Date()
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.2, direction: .right, began: true, ended: false),
                now: now,
                commitThreshold: 0.08
            )
        )
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: -0.05, direction: .left, began: false, ended: false),
                now: now.addingTimeInterval(0.1),
                commitThreshold: 0.08
            )
        )
        // Peak stays at the rightmost sample (0.2); ending left still commits right if peak passed threshold.
        // A true reverse below threshold peak should not hop: keep peak under threshold.
        tracker = SwipeGestureTracker()
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.04, direction: .right, began: true, ended: false),
                now: now,
                commitThreshold: 0.08
            )
        )
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: -0.03, direction: .left, began: false, ended: true),
                now: now.addingTimeInterval(0.1),
                commitThreshold: 0.08
            )
        )
    }

    func testPeakPastThresholdHopsOnce() {
        var tracker = SwipeGestureTracker()
        let now = Date()
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.12, direction: .right, began: true, ended: false),
                now: now,
                commitThreshold: 0.08
            )
        )
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.15, direction: .right, began: false, ended: false),
                now: now.addingTimeInterval(0.05),
                commitThreshold: 0.08
            )
        )
        // Peak (>= 0.08) commits a single hop on ended; progress at lift can be smaller.
        XCTAssertEqual(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.05, direction: .right, began: false, ended: true),
                now: now.addingTimeInterval(0.2),
                commitThreshold: 0.08
            ),
            .next
        )
        XCTAssertFalse(tracker.isSwallowing)
    }

    func testEndedBelowThresholdDoesNotHop() {
        var tracker = SwipeGestureTracker()
        let now = Date()
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.05, direction: .left, began: true, ended: false),
                now: now,
                commitThreshold: 0.08
            )
        )
        XCTAssertNil(
            tracker.consume(
                DockSwipeSwitcher.HorizontalSwipe(progress: 0.02, direction: .left, began: false, ended: true),
                now: now.addingTimeInterval(0.1),
                commitThreshold: 0.08
            )
        )
    }
}
