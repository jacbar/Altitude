@testable import Altitude
import XCTest

final class ConfigApplyTests: XCTestCase {
    func testToggledDesired() {
        XCTAssertFalse(ConfigApply.toggledDesired(isEnabled: true, requiresApproval: false))
        XCTAssertFalse(ConfigApply.toggledDesired(isEnabled: false, requiresApproval: true))
        XCTAssertFalse(ConfigApply.toggledDesired(isEnabled: true, requiresApproval: true))
        XCTAssertTrue(ConfigApply.toggledDesired(isEnabled: false, requiresApproval: false))
    }

    func testSetLaunchAtLoginLeavesConfigWhenServiceThrows() {
        var enabledCalls: [Bool] = []
        var saveCalls = 0
        let config = AppConfig.default
        let result = ConfigApply.setLaunchAtLogin(
            desired: true,
            config: config,
            setEnabled: { desired in
                enabledCalls.append(desired)
                throw TestError.service
            },
            save: { _ in
                saveCalls += 1
            }
        )
        XCTAssertEqual(result, config)
        XCTAssertEqual(enabledCalls, [true])
        XCTAssertEqual(saveCalls, 0)
    }

    func testSetLaunchAtLoginRollsBackServiceWhenSaveThrows() {
        var enabledCalls: [Bool] = []
        let config = AppConfig.default
        XCTAssertFalse(config.launchAtLogin)
        let result = ConfigApply.setLaunchAtLogin(
            desired: true,
            config: config,
            setEnabled: { desired in
                enabledCalls.append(desired)
            },
            save: { _ in
                throw TestError.save
            }
        )
        XCTAssertEqual(result, config)
        XCTAssertEqual(enabledCalls, [true, false])
    }

    func testSetLaunchAtLoginPersistsOnSuccess() {
        var saved: AppConfig?
        let config = AppConfig.default
        let result = ConfigApply.setLaunchAtLogin(
            desired: true,
            config: config,
            setEnabled: { _ in },
            save: { saved = $0 }
        )
        XCTAssertTrue(result.launchAtLogin)
        XCTAssertEqual(saved?.launchAtLogin, true)
    }

    func testSavingReturnsPreviousWhenSaveThrows() {
        let previous = AppConfig.default
        var updated = previous
        updated.launchAtLogin = true
        let result = ConfigApply.saving(previous: previous, updated: updated) { _ in
            throw TestError.save
        }
        XCTAssertEqual(result, previous)
    }

    func testSavingReturnsUpdatedOnSuccess() {
        let previous = AppConfig.default
        var updated = previous
        updated.launchAtLogin = true
        let result = ConfigApply.saving(previous: previous, updated: updated) { _ in }
        XCTAssertEqual(result, updated)
    }
}

private enum TestError: Error {
    case service
    case save
}
