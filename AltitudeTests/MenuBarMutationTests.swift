import XCTest

final class MenuBarMutationTests: XCTestCase {
    private struct FakeError: Error {}

    func testSetLaunchAtLoginServiceFailureLeavesConfigPathUnchanged() {
        var saved: Bool?
        var setCalls: [Bool] = []
        let outcome = MenuBarMutation.setLaunchAtLogin(
            desired: true,
            previous: false,
            setEnabled: { value in
                setCalls.append(value)
                throw FakeError()
            },
            save: {
                saved = true
            }
        )
        XCTAssertEqual(outcome, .serviceFailed)
        XCTAssertEqual(setCalls, [true])
        XCTAssertNil(saved)
    }

    func testSetLaunchAtLoginSaveFailureRestoresPreviousLoginItem() {
        var setCalls: [Bool] = []
        let outcome = MenuBarMutation.setLaunchAtLogin(
            desired: true,
            previous: false,
            setEnabled: { value in
                setCalls.append(value)
            },
            save: {
                throw FakeError()
            }
        )
        XCTAssertEqual(outcome, .saveFailedRestored(previous: false))
        XCTAssertEqual(setCalls, [true, false])
    }

    func testApplyWriteSaveFailure() {
        XCTAssertEqual(
            MenuBarMutation.applyWrite(write: true, save: { throw FakeError() }),
            .saveFailed
        )
        XCTAssertEqual(
            MenuBarMutation.applyWrite(write: false, save: { throw FakeError() }),
            .succeeded
        )
        XCTAssertEqual(
            MenuBarMutation.applyWrite(write: true, save: {}),
            .succeeded
        )
    }
}
