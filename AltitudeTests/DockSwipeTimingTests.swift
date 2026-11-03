import XCTest

final class DockSwipeTimingTests: XCTestCase {
    func testInstantOrZeroStepsReturnsZero() {
        XCTAssertEqual(DockSwipeTiming.estimatedDuration(steps: 3, instant: true), 0)
        XCTAssertEqual(DockSwipeTiming.estimatedDuration(steps: 0, instant: false), 0)
        XCTAssertEqual(DockSwipeTiming.estimatedDuration(steps: -1, instant: false), 0)
    }

    func testOneStepEqualsFrameCountTimesInterval() {
        let expected = Double(DockSwipeTiming.smoothFrameCount) * DockSwipeTiming.smoothFrameInterval
        XCTAssertEqual(DockSwipeTiming.estimatedDuration(steps: 1, instant: false), expected)
    }

    func testInstantLandingDelayUsesBaseAndPerStep() {
        XCTAssertEqual(Timing.instantLandingDelay(steps: 1), 0.14)
        XCTAssertEqual(Timing.instantLandingDelay(steps: 3), 0.26)
        XCTAssertEqual(Timing.instantLandingDelay(steps: 0), Timing.instantLandingDelay(steps: 1))
        XCTAssertEqual(Timing.instantLandingDelay(steps: -1), Timing.instantLandingDelay(steps: 1))
    }
}
