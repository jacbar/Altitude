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

    func testConfigSaveGuardProceedWhenBothAbsent() {
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: false,
                recordedModifiedAt: nil,
                currentModifiedAt: nil
            ),
            .proceed
        )
    }

    func testConfigSaveGuardProceedWhenDatesMatch() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: false,
                recordedModifiedAt: date,
                currentModifiedAt: date
            ),
            .proceed
        )
    }

    func testConfigSaveGuardBlockedWhenLoadFailed() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: true,
                recordedModifiedAt: date,
                currentModifiedAt: date
            ),
            .blocked
        )
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: true,
                recordedModifiedAt: nil,
                currentModifiedAt: nil
            ),
            .blocked
        )
    }

    func testConfigSaveGuardReloadWhenFileAppeared() {
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: false,
                recordedModifiedAt: nil,
                currentModifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            .reload
        )
    }

    func testConfigSaveGuardReloadWhenFileDisappeared() {
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: false,
                recordedModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                currentModifiedAt: nil
            ),
            .reload
        )
    }

    func testConfigSaveGuardReloadWhenDateChanged() {
        XCTAssertEqual(
            MenuBarMutation.configSaveGuard(
                loadFailed: false,
                recordedModifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                currentModifiedAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
            .reload
        )
    }
}
