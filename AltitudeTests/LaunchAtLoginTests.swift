import XCTest

final class LaunchAtLoginTests: XCTestCase {
    func testToggledDesired() {
        XCTAssertFalse(LaunchAtLogin.toggledDesired(isEnabled: true, requiresApproval: false))
        XCTAssertFalse(LaunchAtLogin.toggledDesired(isEnabled: false, requiresApproval: true))
        XCTAssertFalse(LaunchAtLogin.toggledDesired(isEnabled: true, requiresApproval: true))
        XCTAssertTrue(LaunchAtLogin.toggledDesired(isEnabled: false, requiresApproval: false))
    }
}
