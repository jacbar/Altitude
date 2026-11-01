@testable import Altitude
import CoreGraphics
import XCTest

final class WindowFrameTests: XCTestCase {
    func testAccessibilityOrigin() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        let origin = WindowArrangement.accessibilityOrigin(cocoaRect: rect, primaryScreenMaxY: 1000)
        XCTAssertEqual(origin.x, 100)
        XCTAssertEqual(origin.y, 650) // 1000 - 350
    }

    func testNeedsAnotherPass() {
        let written = CGRect(x: 10, y: 20, width: 100, height: 200)
        XCTAssertFalse(WindowArrangement.needsAnotherPass(written: written, readBack: written))
        XCTAssertFalse(
            WindowArrangement.needsAnotherPass(
                written: written,
                readBack: CGRect(x: 10.5, y: 20.4, width: 100.2, height: 199.5)
            )
        )
        XCTAssertTrue(
            WindowArrangement.needsAnotherPass(
                written: written,
                readBack: CGRect(x: 12, y: 20, width: 100, height: 200)
            )
        )
    }
}
