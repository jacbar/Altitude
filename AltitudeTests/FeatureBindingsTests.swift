import XCTest

final class FeatureBindingsTests: XCTestCase {
    func testDesktopBindingsDisabledEmpty() {
        var config = AppConfig.default
        config.desktop.enabled = false
        XCTAssertTrue(DesktopFeature.bindings(config: config, spaceCount: 5).isEmpty)
    }

    func testDesktopBindingsIdsAndMaxSpaceFloor() {
        var config = AppConfig.default
        config.desktop.enabled = true
        config.desktop.maxSpace = 0
        let bindings = DesktopFeature.bindings(config: config, spaceCount: 0)
        XCTAssertFalse(bindings.isEmpty)
        XCTAssertEqual(bindings.map(\.id), [
            HotkeyID.switchDesktop(1),
            HotkeyID.moveDesktop(1),
        ])
    }

    func testWindowManagementBindingsDisabledEmpty() {
        var config = AppConfig.default
        config.windowManagement.enabled = false
        XCTAssertTrue(WindowManagementFeature.bindings(config: config).isEmpty)
    }

    func testWindowManagementBindingsEnabledIds() {
        let bindings = WindowManagementFeature.bindings(config: .default)
        XCTAssertEqual(bindings.map(\.id), [HotkeyID.maximize, HotkeyID.equalSplit])
    }

    func testCommandTabMotionMode() {
        let off = CommandTabFeature.motionMode(config: .default)
        XCTAssertEqual(off, .off)

        var commandTabOn = AppConfig.default
        commandTabOn.commandTab.enabled = true
        let tabMode = CommandTabFeature.motionMode(config: commandTabOn)
        XCTAssertTrue(tabMode.commandTabEnabled)
        XCTAssertFalse(tabMode.commandTabInstantLanding)
        XCTAssertFalse(tabMode.suppressDesktopMotion)

        var desktopMotion = AppConfig.default
        desktopMotion.desktop.disableMotion = true
        let desktopMode = CommandTabFeature.motionMode(config: desktopMotion)
        XCTAssertTrue(desktopMode.suppressDesktopMotion)
        XCTAssertFalse(desktopMode.commandTabEnabled)
        XCTAssertTrue(desktopMode.wantsTaps)
    }
}
