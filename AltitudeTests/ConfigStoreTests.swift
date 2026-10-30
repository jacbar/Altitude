import XCTest
@testable import Altitude

final class ConfigStoreTests: XCTestCase {
    func testEmptyAndWhitespaceYieldDefaults() {
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig(""), .default)
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig("   \n\t\n  "), .default)
    }

    func testHappyPathAllKeys() {
        let text = """
        version = 2

        [app]
        launch_at_login = true

        [spaces]
        disable_animations = true
        disable_system_motions = true

        [hotkeys]
        switch_enabled = false
        move_enabled = false
        max_space = 5
        """
        let config = MinimalTOML.parseAltitudeConfig(text)
        XCTAssertEqual(config.version, 2)
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertTrue(config.disableAnimations)
        XCTAssertTrue(config.disableSystemMotions)
        XCTAssertFalse(config.switchEnabled)
        XCTAssertFalse(config.moveEnabled)
        XCTAssertEqual(config.maxSpace, 5)
    }

    func testMaxSpaceClamp() {
        XCTAssertEqual(parseMaxSpace(0), 1)
        XCTAssertEqual(parseMaxSpace(9), 9)
        XCTAssertEqual(parseMaxSpace(16), 9)
        XCTAssertEqual(parseMaxSpace(17), 9)
        XCTAssertEqual(parseMaxSpace(-3), 1)
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
            [hotkeys]
            switch_enabled = \(falseValue)
            """)
            XCTAssertFalse(config.switchEnabled, falseValue)
        }
    }

    func testInvalidAndQuotedValuesKeepDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        version = "two"
        [app]
        launch_at_login = "true"
        [spaces]
        disable_animations = maybe
        [hotkeys]
        switch_enabled = yeah
        move_enabled = nah
        max_space = "9"
        """)
        XCTAssertEqual(config, .default)
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
        XCTAssertEqual(config.maxSpace, AppConfig.default.maxSpace)
    }

    func testPartialFileMergesDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [hotkeys]
        max_space = 4
        """)
        XCTAssertEqual(config.maxSpace, 4)
        XCTAssertEqual(config.version, AppConfig.default.version)
        XCTAssertEqual(config.switchEnabled, AppConfig.default.switchEnabled)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
    }

    func testMissingArrangeKeepsDefaults() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [hotkeys]
        max_space = 4
        """)
        XCTAssertEqual(config.arrangeMargin, 8)
        XCTAssertTrue(config.arrangeMaximizeEnabled)
        XCTAssertTrue(config.arrangeColumnsEnabled)
    }

    func testArrangeMarginClamp() {
        XCTAssertEqual(parseArrangeMargin(-1), 0)
        XCTAssertEqual(parseArrangeMargin(0), 0)
        XCTAssertEqual(parseArrangeMargin(8), 8)
        XCTAssertEqual(parseArrangeMargin(256), 256)
        XCTAssertEqual(parseArrangeMargin(257), 256)
    }

    func testInvalidArrangeMarginKeepsDefault() {
        let config = MinimalTOML.parseAltitudeConfig("""
        [arrange]
        margin = eight
        """)
        XCTAssertEqual(config.arrangeMargin, 8)
    }

    func testArrangeBoolFlags() {
        for trueValue in ["true", "yes", "1", "TRUE", "Yes"] {
            let config = MinimalTOML.parseAltitudeConfig("""
            [arrange]
            maximize_enabled = \(trueValue)
            columns_enabled = \(trueValue)
            """)
            XCTAssertTrue(config.arrangeMaximizeEnabled, trueValue)
            XCTAssertTrue(config.arrangeColumnsEnabled, trueValue)
        }
        for falseValue in ["false", "no", "0", "FALSE", "No"] {
            let config = MinimalTOML.parseAltitudeConfig("""
            [arrange]
            maximize_enabled = \(falseValue)
            columns_enabled = \(falseValue)
            """)
            XCTAssertFalse(config.arrangeMaximizeEnabled, falseValue)
            XCTAssertFalse(config.arrangeColumnsEnabled, falseValue)
        }
    }

    func testSaveShapedTextRoundTrip() {
        let original = AppConfig(
            version: 1,
            launchAtLogin: true,
            disableAnimations: true,
            disableSystemMotions: false,
            switchEnabled: true,
            moveEnabled: false,
            maxSpace: 7,
            arrangeMargin: 12,
            arrangeMaximizeEnabled: false,
            arrangeColumnsEnabled: true
        )
        let text = """
        version = \(original.version)

        [app]
        launch_at_login = true

        [spaces]
        disable_animations = true
        disable_system_motions = false

        [hotkeys]
        switch_enabled = true
        move_enabled = false
        max_space = \(original.maxSpace)

        [arrange]
        margin = \(original.arrangeMargin)
        maximize_enabled = false
        columns_enabled = true
        """
        XCTAssertEqual(MinimalTOML.parseAltitudeConfig(text), original)
    }

    private func parseMaxSpace(_ value: Int) -> Int {
        MinimalTOML.parseAltitudeConfig("""
        [hotkeys]
        max_space = \(value)
        """).maxSpace
    }

    private func parseArrangeMargin(_ value: Int) -> Int {
        MinimalTOML.parseAltitudeConfig("""
        [arrange]
        margin = \(value)
        """).arrangeMargin
    }
}
