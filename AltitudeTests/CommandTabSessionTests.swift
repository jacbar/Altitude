import XCTest

final class CommandTabSessionTests: XCTestCase {
    func testOpenWithOneTargetIsNil() {
        let now = Date()
        XCTAssertNil(CommandTabSession.open(targets: ["only"], index: 0, now: now))
    }

    func testMovePlusOneWrapsFromLastToZero() {
        let now = Date()
        var session = CommandTabSession.open(targets: ["a", "b", "c"], index: 2, now: now)!
        XCTAssertFalse(session.move(by: 1, now: now.addingTimeInterval(1)))
        XCTAssertEqual(session.index, 0)
    }

    func testMoveMinusOneWrapsFromZeroToLast() {
        let now = Date()
        var session = CommandTabSession.open(targets: ["a", "b", "c"], index: 0, now: now)!
        XCTAssertFalse(session.move(by: -1, now: now.addingTimeInterval(1)))
        XCTAssertEqual(session.index, 2)
    }

    func testOpenAndMoveSetIdleDeadlineToNowPlusTen() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var session = CommandTabSession.open(targets: ["a", "b"], index: 0, now: now)!
        XCTAssertEqual(session.idleDeadline, now.addingTimeInterval(Timing.commandTabIdle))
        XCTAssertEqual(Timing.commandTabIdle, 10)

        let later = now.addingTimeInterval(3)
        XCTAssertFalse(session.move(by: 1, now: later))
        XCTAssertEqual(session.idleDeadline, later.addingTimeInterval(Timing.commandTabIdle))
    }
}
