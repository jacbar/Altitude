import CoreGraphics
import XCTest
@testable import Altitude

final class WindowArrangementTests: XCTestCase {
    func testMaximizedRectDefaultMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = WindowArrangement.maximizedRect(visibleFrame: visible, margin: 8)
        XCTAssertEqual(rect, CGRect(x: 8, y: 8, width: 984, height: 784))
    }

    func testMaximizedRectZeroMarginUnchanged() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(
            WindowArrangement.maximizedRect(visibleFrame: visible, margin: 0),
            visible
        )
    }

    func testMaximizedRectTooLargeMarginIsNil() {
        let visible = CGRect(x: 0, y: 0, width: 150, height: 800)
        XCTAssertNil(WindowArrangement.maximizedRect(visibleFrame: visible, margin: 100))
    }

    func testColumnRectsCountOneMatchesMaximize() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let maximized = WindowArrangement.maximizedRect(visibleFrame: visible, margin: 8)
        let columns = WindowArrangement.columnRects(visibleFrame: visible, margin: 8, count: 1)
        XCTAssertEqual(columns, maximized.map { [$0] })
    }

    func testColumnRectsCountZeroIsNil() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertNil(WindowArrangement.columnRects(visibleFrame: visible, margin: 8, count: 0))
    }

    func testColumnRectsTwoColumns() {
        let visible = CGRect(x: 100, y: 40, width: 230, height: 800)
        let columns = WindowArrangement.columnRects(visibleFrame: visible, margin: 10, count: 2)
        XCTAssertEqual(
            columns,
            [
                CGRect(x: 110, y: 50, width: 100, height: 780),
                CGRect(x: 220, y: 50, width: 100, height: 780),
            ]
        )
    }

    func testColumnRectsThreeNoMargin() {
        let visible = CGRect(x: 0, y: 0, width: 900, height: 300)
        let columns = WindowArrangement.columnRects(visibleFrame: visible, margin: 0, count: 3)
        XCTAssertEqual(
            columns,
            [
                CGRect(x: 0, y: 0, width: 300, height: 300),
                CGRect(x: 300, y: 0, width: 300, height: 300),
                CGRect(x: 600, y: 0, width: 300, height: 300),
            ]
        )
    }

    func testSortIndicesLeftThenTop() {
        XCTAssertEqual(
            WindowArrangement.sortIndices(left: [10, 0, 10], top: [5, 1, 1]),
            [1, 2, 0]
        )
    }

    func testAcceptsArrangeRole() {
        XCTAssertTrue(WindowArrangement.acceptsArrangeRole(""))
        XCTAssertTrue(WindowArrangement.acceptsArrangeRole("AXWindow"))
        XCTAssertFalse(WindowArrangement.acceptsArrangeRole("AXButton"))
        XCTAssertFalse(WindowArrangement.acceptsArrangeRole("AXGroup"))
    }

    func testAcceptsArrangeSubrole() {
        // Empty / standard / Electron-style non-standard all included.
        XCTAssertTrue(WindowArrangement.acceptsArrangeSubrole(""))
        XCTAssertTrue(WindowArrangement.acceptsArrangeSubrole("AXStandardWindow"))
        XCTAssertTrue(WindowArrangement.acceptsArrangeSubrole("AXDialog"))
        XCTAssertTrue(WindowArrangement.acceptsArrangeSubrole("AXFloatingWindow"))
        XCTAssertTrue(WindowArrangement.acceptsArrangeSubrole("AXDocumentWindow"))
        // Match Command-Tab AX exclusions only.
        XCTAssertFalse(WindowArrangement.acceptsArrangeSubrole("AXUnknown"))
        XCTAssertFalse(WindowArrangement.acceptsArrangeSubrole("AXSystemDialog"))
    }

    func testSpaceMembershipOnArrangeSpace() {
        XCTAssertEqual(
            WindowArrangement.spaceMembership(
                windowSpaceIDs: [7, 3],
                arrangeSpaceID: 3,
                activeSpaceID: 9
            ),
            .onArrangeSpace
        )
    }

    func testSpaceMembershipEmptyOnActiveArrangeSpace() {
        XCTAssertEqual(
            WindowArrangement.spaceMembership(
                windowSpaceIDs: [],
                arrangeSpaceID: 5,
                activeSpaceID: 5
            ),
            .emptyOnActiveArrangeSpace
        )
    }

    func testSpaceMembershipEmptyWhenArrangeIsNotActiveIsExcluded() {
        XCTAssertEqual(
            WindowArrangement.spaceMembership(
                windowSpaceIDs: [],
                arrangeSpaceID: 5,
                activeSpaceID: 9
            ),
            .excluded
        )
    }

    func testSpaceMembershipOtherSpaceIsExcluded() {
        XCTAssertEqual(
            WindowArrangement.spaceMembership(
                windowSpaceIDs: [2, 8],
                arrangeSpaceID: 5,
                activeSpaceID: 5
            ),
            .excluded
        )
    }

    func testThreeIncludedWindowsYieldThreeColumnRects() {
        let visible = CGRect(x: 0, y: 0, width: 940, height: 600)
        let columns = WindowArrangement.columnRects(visibleFrame: visible, margin: 10, count: 3)
        XCTAssertEqual(columns?.count, 3)
        XCTAssertEqual(
            columns,
            [
                CGRect(x: 10, y: 10, width: 300, height: 580),
                CGRect(x: 320, y: 10, width: 300, height: 580),
                CGRect(x: 630, y: 10, width: 300, height: 580),
            ]
        )
    }
}
