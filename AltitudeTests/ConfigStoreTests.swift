import XCTest

final class ConfigStoreTests: XCTestCase {
    func testEmptyAndWhitespaceYieldDefaults() {
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig(""), .default)
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig("   \n\t\n  "), .default)
    }

    func testOldSectionKeysDoNothing() {
        let config = MinimalTOML.parseAltitudeConfig("""
        version = 1

        [spaces]
        disable_animations = true
        disable_system_motions = true

        [hotkeys]
        switch_enabled = false
        move_enabled = false
        max_space = 3

        [arrange]
        margin = 99
        maximize_enabled = false
        columns_enabled = false
        """)
        XCTAssertEqual(config.desktop, AppConfig.default.desktop)
        XCTAssertEqual(config.commandTab, AppConfig.default.commandTab)
        XCTAssertEqual(config.windowManagement, AppConfig.default.windowManagement)
        // Root version is still read.
        XCTAssertEqual(config.version, 1)
    }

    func testDesktopEnabledFlag() {
        let off = MinimalTOML.parseAltitudeConfig("""
        [desktop]
        enabled = false
        """)
        XCTAssertFalse(off.desktop.enabled)
        XCTAssertTrue(DesktopFeature.bindings(config: off, spaceCount: 5).isEmpty)
        XCTAssertFalse(DesktopFeature.instantSwitching(config: off))

        var withMotion = AppConfig.default
        withMotion.desktop.disableMotion = true
        XCTAssertTrue(DesktopFeature.instantSwitching(config: withMotion))
        withMotion.desktop.enabled = false
        XCTAssertFalse(DesktopFeature.instantSwitching(config: withMotion))
    }

    func testCommandTabEnabledFlag() {
        let off = AppConfig.default
        let offMode = CommandTabFeature.motionMode(config: off)
        XCTAssertFalse(offMode.commandTabEnabled)
        XCTAssertFalse(offMode.commandTabInstantLanding)

        var on = AppConfig.default
        on.commandTab.enabled = true
        on.commandTab.disableMotion = true
        on.desktop.disableMotion = true
        let mode = CommandTabFeature.motionMode(config: on)
        XCTAssertTrue(mode.commandTabEnabled)
        XCTAssertTrue(mode.commandTabInstantLanding)
        XCTAssertTrue(mode.suppressDesktopMotion)

        // Desktop disable_motion alone still works while Command-Tab stays off.
        var desktopOnly = AppConfig.default
        desktopOnly.desktop.disableMotion = true
        let desktopMode = CommandTabFeature.motionMode(config: desktopOnly)
        XCTAssertFalse(desktopMode.commandTabEnabled)
        XCTAssertTrue(desktopMode.suppressDesktopMotion)
        XCTAssertTrue(desktopMode.wantsTaps)
    }

    func testWindowManagementEnabledFlag() {
        var off = AppConfig.default
        off.windowManagement.enabled = false
        XCTAssertTrue(WindowManagementFeature.bindings(config: off).isEmpty)

        let on = AppConfig.default
        let bindings = WindowManagementFeature.bindings(config: on)
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings.map(\.id), [200, 201])
    }

    func testMissingShortcutSectionsUseDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [desktop]
        enabled = true
        max_space = 4

        [window_management]
        enabled = true
        margin = 12
        """)
        XCTAssertEqual(config.desktop.switchModifiers, .optionOnly)
        XCTAssertEqual(config.desktop.moveModifiers, .optionShift)
        XCTAssertEqual(config.windowManagement.maximize, .maximizeDefault)
        XCTAssertEqual(config.windowManagement.equalSplit, .equalSplitDefault)
        XCTAssertEqual(config.desktop.maxSpace, 4)
        XCTAssertEqual(config.windowManagement.margin, 12)
    }

    func testEmptyModifierSetsFallBack() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [desktop.switch]
        alt = false
        shift = false
        ctrl = false
        cmd = false

        [desktop.move]
        alt = true
        shift = true
        ctrl = false
        cmd = false
        """)
        XCTAssertEqual(config.desktop.switchModifiers, .optionOnly)
        XCTAssertEqual(config.desktop.moveModifiers, .optionShift)
    }

    func testIdenticalSwitchMoveSetsFallBack() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [desktop.switch]
        alt = true
        shift = true
        ctrl = false
        cmd = false

        [desktop.move]
        alt = true
        shift = true
        ctrl = false
        cmd = false
        """)
        XCTAssertEqual(config.desktop.switchModifiers, .optionOnly)
        XCTAssertEqual(config.desktop.moveModifiers, .optionShift)
    }

    func testInvalidAndEmptyWindowKeysFallBack() {
        let quoted = MinimalTOML.parseAltitudeConfig("""
        [window_management.maximize]
        key = "f"
        """)
        XCTAssertEqual(quoted.windowManagement.maximize.key, "f")
        XCTAssertEqual(quoted.windowManagement.maximize.modifiers, .controlOption)

        let empty = MinimalTOML.parseAltitudeConfig("""
        [window_management.equal_split]
        key =
        """)
        XCTAssertEqual(empty.windowManagement.equalSplit, .equalSplitDefault)

        let bad = MinimalTOML.parseAltitudeConfig("""
        [window_management.maximize]
        key = 1
        """)
        XCTAssertEqual(bad.windowManagement.maximize, .maximizeDefault)

        let caseInsensitive = MinimalTOML.parseAltitudeConfig("""
        [window_management.maximize]
        key = F
        """)
        XCTAssertEqual(caseInsensitive.windowManagement.maximize.key, "f")
    }

    func testIdenticalWindowChordsFallBack() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [window_management.maximize]
        alt = true
        shift = false
        ctrl = true
        cmd = false
        key = a

        [window_management.equal_split]
        alt = true
        shift = false
        ctrl = true
        cmd = false
        key = a
        """)
        XCTAssertEqual(config.windowManagement.maximize, .maximizeDefault)
        XCTAssertEqual(config.windowManagement.equalSplit, .equalSplitDefault)
    }

    func testMaxSpaceAndMarginClamps() {
        XCTAssertEqual(parseMaxSpace(0), 1)
        XCTAssertEqual(parseMaxSpace(9), 9)
        XCTAssertEqual(parseMaxSpace(16), 9)
        XCTAssertEqual(parseMaxSpace(-3), 1)

        XCTAssertEqual(parseMargin(-1), 0)
        XCTAssertEqual(parseMargin(0), 0)
        XCTAssertEqual(parseMargin(8), 8)
        XCTAssertEqual(parseMargin(256), 256)
        XCTAssertEqual(parseMargin(257), 256)
    }

    func testInvalidBoolsAndIntsKeepDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        version = "two"
        [app]
        launch_at_login = "true"
        [desktop]
        enabled = maybe
        disable_motion = yeah
        max_space = "9"
        [window_management]
        margin = eight
        """)
        XCTAssertEqual(config.version, AppConfig.default.version)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
        XCTAssertEqual(config.desktop.enabled, AppConfig.default.desktop.enabled)
        XCTAssertEqual(config.desktop.disableMotion, AppConfig.default.desktop.disableMotion)
        XCTAssertEqual(config.desktop.maxSpace, AppConfig.default.desktop.maxSpace)
        XCTAssertEqual(config.windowManagement.margin, AppConfig.default.windowManagement.margin)
    }

    func testBoolSynonyms() {
        for trueValue in ["true", "yes", "1", "TRUE", "Yes"] {
            let config = MinimalTOML.parseAltitudeConfig("""
            [app]
            launch_at_login = \(trueValue)
            """)
            XCTAssertTrue(config.launchAtLogin, trueValue)
        }
        for falseValue in ["false", "no", "0", "FALSE", "No"] {
            let config = MinimalTOML.parseAltitudeConfig("""
            [desktop]
            enabled = \(falseValue)
            """)
            XCTAssertFalse(config.desktop.enabled, falseValue)
        }
    }

    func testCommentsAreIgnored() {
        let config = MinimalTOML.parseAltitudeConfig("""
        # top comment
        version = 3 # trailing
        [app] # section
        launch_at_login = true # ok
        """)
        XCTAssertEqual(config.version, 3)
        XCTAssertTrue(config.launchAtLogin)
    }

    func testUnknownKeysAreIgnored() {
        let config = MinimalTOML.parseAltitudeConfig("""
        mystery = 1
        [app]
        launch_at_login = true
        extra = false
        [other]
        foo = bar
        """)
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertEqual(config.desktop.maxSpace, AppConfig.default.desktop.maxSpace)
    }

    func testPartialModifiersKeepDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [desktop.switch]
        ctrl = true
        """)
        // Missing alt/shift/cmd keep Option-only defaults → alt true, shift false, cmd false, ctrl true.
        XCTAssertTrue(config.desktop.switchModifiers.alt)
        XCTAssertFalse(config.desktop.switchModifiers.shift)
        XCTAssertTrue(config.desktop.switchModifiers.ctrl)
        XCTAssertFalse(config.desktop.switchModifiers.cmd)
    }

    func testSaveShapedTextRoundTrip() {
        let original = AppConfig(
            version: 2,
            launchAtLogin: true,
            desktop: DesktopConfig(
                enabled: true,
                disableMotion: true,
                maxSpace: 7,
                switchModifiers: ModifierFlags(alt: true, shift: false, ctrl: true, cmd: false),
                moveModifiers: ModifierFlags(alt: true, shift: true, ctrl: false, cmd: false)
            ),
            commandTab: CommandTabConfig(enabled: true, disableMotion: false),
            windowManagement: WindowManagementConfig(
                enabled: true,
                margin: 12,
                maximize: KeyChord(
                    modifiers: ModifierFlags(alt: true, shift: false, ctrl: true, cmd: false),
                    key: "f"
                ),
                equalSplit: KeyChord(
                    modifiers: ModifierFlags(alt: true, shift: false, ctrl: true, cmd: false),
                    key: "a"
                )
            )
        )
        let text = """
        version = \(original.version)

        [app]
        launch_at_login = true

        [desktop]
        enabled = true
        disable_motion = true
        max_space = \(original.desktop.maxSpace)

        [desktop.switch]
        alt = true
        shift = false
        ctrl = true
        cmd = false

        [desktop.move]
        alt = true
        shift = true
        ctrl = false
        cmd = false

        [command_tab]
        enabled = true
        disable_motion = false

        [window_management]
        enabled = true
        margin = \(original.windowManagement.margin)

        [window_management.maximize]
        alt = true
        shift = false
        ctrl = true
        cmd = false
        key = f

        [window_management.equal_split]
        alt = true
        shift = false
        ctrl = true
        cmd = false
        key = a
        """
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig(text), original)
    }

    private func parseMaxSpace(_ value: Int) -> Int {
        MinimalTOML.parseAltitudeConfig("""
        [desktop]
        max_space = \(value)
        """).desktop.maxSpace
    }

    private func parseMargin(_ value: Int) -> Int {
        MinimalTOML.parseAltitudeConfig("""
        [window_management]
        margin = \(value)
        """).windowManagement.margin
    }
}
