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

    func testAppShortcutsBindingsDisabledEmpty() {
        var config = AppConfig.default
        config.appShortcuts.enabled = false
        config.appShortcuts.entries = [
            AppShortcutEntry(
                bundleID: "com.apple.Safari",
                chord: KeyChord(modifiers: .controlOption, key: "s")
            ),
        ]
        XCTAssertTrue(AppShortcutsFeature.bindings(config: config).isEmpty)
    }

    func testAppShortcutsBindingsEnabledIdsSkipEmptyBundle() {
        var config = AppConfig.default
        config.appShortcuts.enabled = true
        config.appShortcuts.entries = [
            AppShortcutEntry(
                bundleID: "com.apple.Safari",
                chord: KeyChord(modifiers: .controlOption, key: "s")
            ),
            AppShortcutEntry(
                bundleID: "",
                chord: KeyChord(modifiers: .controlOption, key: "t")
            ),
            AppShortcutEntry(
                bundleID: "com.apple.Terminal",
                chord: KeyChord(modifiers: .optionShift, key: "t")
            ),
        ]
        let bindings = AppShortcutsFeature.bindings(config: config)
        XCTAssertEqual(bindings.map(\.id), [HotkeyID.appShortcut(0), HotkeyID.appShortcut(2)])
        XCTAssertEqual(bindings.map(\.action), [.jumpToApp(0), .jumpToApp(2)])
    }

    func testAppShortcutsBindingsAcceptDigitChord() {
        var config = AppConfig.default
        config.appShortcuts.enabled = true
        config.appShortcuts.entries = [
            AppShortcutEntry(
                bundleID: "com.apple.Safari",
                chord: KeyChord(
                    modifiers: ModifierFlags(alt: false, shift: false, ctrl: true, cmd: false),
                    key: "1"
                )
            ),
        ]
        let bindings = AppShortcutsFeature.bindings(config: config)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].keyCode, HotkeyChordMapping.digitCharacterKeyCode("1"))
        XCTAssertEqual(bindings[0].action, .jumpToApp(0))
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
