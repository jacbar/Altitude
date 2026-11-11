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

    func testSelectInRangeUpdatesIndexAndIdle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var session = CommandTabSession.open(targets: ["a", "b", "c"], index: 0, now: now)!
        let later = now.addingTimeInterval(4)
        XCTAssertFalse(session.select(index: 2, now: later))
        XCTAssertEqual(session.index, 2)
        XCTAssertEqual(session.idleDeadline, later.addingTimeInterval(Timing.commandTabIdle))
    }

    func testSelectOutOfRangeCloses() {
        let now = Date()
        var session = CommandTabSession.open(targets: ["a", "b"], index: 0, now: now)!
        XCTAssertTrue(session.select(index: -1, now: now))
        XCTAssertTrue(session.select(index: 2, now: now))
    }

    func testSelectSameIndexRefreshesIdle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var session = CommandTabSession.open(targets: ["a", "b"], index: 1, now: now)!
        let later = now.addingTimeInterval(5)
        XCTAssertFalse(session.select(index: 1, now: later))
        XCTAssertEqual(session.index, 1)
        XCTAssertEqual(session.idleDeadline, later.addingTimeInterval(Timing.commandTabIdle))
    }
}
