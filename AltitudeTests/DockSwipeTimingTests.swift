import XCTest

final class DockSwipeTimingTests: XCTestCase {
    func testEstimatedDuration() {
        XCTAssertEqual(DockSwipeSwitcher.estimatedDuration(steps: 3, instant: true), 0)
        XCTAssertEqual(DockSwipeSwitcher.estimatedDuration(steps: 0, instant: false), 0)
        XCTAssertGreaterThan(DockSwipeSwitcher.estimatedDuration(steps: 1, instant: false), 0)
        XCTAssertGreaterThan(
            DockSwipeSwitcher.estimatedDuration(steps: 2, instant: false),
            DockSwipeSwitcher.estimatedDuration(steps: 1, instant: false)
        )
    }
}
