import XCTest

final class CommandTabKeysTests: XCTestCase {
    func testTabMovesForward() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 48,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .move(1)
        )
    }

    func testShiftTabMovesBackward() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 48,
                command: true,
                shift: true,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .move(-1)
        )
    }

    func testArrowsMove() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 123,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .move(-1)
        )
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 124,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .move(1)
        )
    }

    func testEscapeCancels() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 53,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .cancel
        )
    }

    func testCommandQAndH() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 12,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .quit
        )
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 4,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .hide
        )
    }

    func testMissingCommandCommits() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 0,
                command: false,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .commit
        )
    }

    func testRepeatDoesNotMove() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 48,
                command: true,
                shift: false,
                alternate: false,
                control: false,
                isKeyDown: true,
                isRepeat: true
            ),
            .swallow
        )
    }

    func testOptionCommandTabSwallows() {
        XCTAssertEqual(
            CommandTabKeys.action(
                keyCode: 48,
                command: true,
                shift: false,
                alternate: true,
                control: false,
                isKeyDown: true,
                isRepeat: false
            ),
            .swallow
        )
    }
}
