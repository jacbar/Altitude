import Carbon.HIToolbox
import CoreGraphics
import XCTest

final class CommandTabSessionTests: XCTestCase {
    func testMoveWraps() {
        var session = CommandTabSession(targets: ["a", "b", "c"], index: 2)
        session.move(by: 1)
        XCTAssertEqual(session.index, 0)
        session.move(by: -1)
        XCTAssertEqual(session.index, 2)
        session.move(by: 4)
        XCTAssertEqual(session.index, 0)
    }

    func testQuitHideEscapeAndCommandAbsent() {
        XCTAssertEqual(
            commandTabKeyAction(keyCode: Int64(kVK_ANSI_Q), flags: .maskCommand),
            .quit
        )
        XCTAssertEqual(
            commandTabKeyAction(keyCode: Int64(kVK_ANSI_H), flags: .maskCommand),
            .hide
        )
        XCTAssertEqual(
            commandTabKeyAction(keyCode: Int64(kVK_Escape), flags: []),
            .cancel
        )
        XCTAssertEqual(
            commandTabKeyAction(keyCode: Int64(kVK_Tab), flags: []),
            .commit
        )
        XCTAssertEqual(
            commandTabKeyAction(keyCode: Int64(kVK_Tab), flags: [.maskCommand, .maskShift]),
            .move(-1)
        )
    }
}
