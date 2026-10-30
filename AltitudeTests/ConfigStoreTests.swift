import XCTest
@testable import Altitude

final class ConfigStoreTests: XCTestCase {
    func testEmptyAndWhitespaceYieldDefaults() throws {
        XCTAssertEqual(try MinimalTOML.parseAltitudeConfig(""), .default)
        XCTAssertEqual(try MinimalTOML.parseAltitudeConfig("   \n\t\n  "), .default)
    }

    func testHappyPathAllKeys() throws {
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
        let config = try MinimalTOML.parseAltitudeConfig(text)
        XCTAssertEqual(config.version, 2)
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertTrue(config.disableAnimations)
        XCTAssertTrue(config.disableSystemMotions)
        XCTAssertFalse(config.switchEnabled)
        XCTAssertFalse(config.moveEnabled)
        XCTAssertEqual(config.maxSpace, 5)
    }

    func testMaxSpaceClamp() throws {
        XCTAssertEqual(try parseMaxSpace(0), 1)
        XCTAssertEqual(try parseMaxSpace(9), 9)
        XCTAssertEqual(try parseMaxSpace(16), 16)
        XCTAssertEqual(try parseMaxSpace(17), 16)
        XCTAssertEqual(try parseMaxSpace(-3), 1)
    }

    func testBoolSynonyms() throws {
        for trueValue in ["true", "yes", "1", "TRUE", "Yes"] {
            let config = try MinimalTOML.parseAltitudeConfig("""
            [app]
            launch_at_login = \(trueValue)
            """)
            XCTAssertTrue(config.launchAtLogin, trueValue)
        }
        for falseValue in ["false", "no", "0", "FALSE", "No"] {
            let config = try MinimalTOML.parseAltitudeConfig("""
            [hotkeys]
            switch_enabled = \(falseValue)
            """)
            XCTAssertFalse(config.switchEnabled, falseValue)
        }
    }

    func testInvalidAndQuotedValuesKeepDefaults() throws {
        let config = try MinimalTOML.parseAltitudeConfig("""
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

    func testCommentsAreIgnored() throws {
        let config = try MinimalTOML.parseAltitudeConfig("""
        # top comment
        version = 3 # trailing
        [app] # section
        launch_at_login = true # ok
        """)
        XCTAssertEqual(config.version, 3)
        XCTAssertTrue(config.launchAtLogin)
    }

    func testUnknownKeysAreIgnored() throws {
        let config = try MinimalTOML.parseAltitudeConfig("""
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

    func testPartialFileMergesDefaults() throws {
        let config = try MinimalTOML.parseAltitudeConfig("""
        [hotkeys]
        max_space = 4
        """)
        XCTAssertEqual(config.maxSpace, 4)
        XCTAssertEqual(config.version, AppConfig.default.version)
        XCTAssertEqual(config.switchEnabled, AppConfig.default.switchEnabled)
        XCTAssertEqual(config.launchAtLogin, AppConfig.default.launchAtLogin)
    }

    func testSaveShapedTextRoundTrip() throws {
        let original = AppConfig(
            version: 1,
            launchAtLogin: true,
            disableAnimations: true,
            disableSystemMotions: false,
            switchEnabled: true,
            moveEnabled: false,
            maxSpace: 7
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
        """
        XCTAssertEqual(try MinimalTOML.parseAltitudeConfig(text), original)
    }

    private func parseMaxSpace(_ value: Int) throws -> Int {
        try MinimalTOML.parseAltitudeConfig("""
        [hotkeys]
        max_space = \(value)
        """).maxSpace
    }
}
