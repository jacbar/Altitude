import Carbon
import XCTest

final class HotkeyMappingTests: XCTestCase {
    func testHotkeyIdsAreUniqueAcrossFeatures() {
        let config = AppConfig.default
        let bindings = DesktopFeature.bindings(config: config, spaceCount: 9)
            + WindowManagementFeature.bindings(config: config)
        let ids = bindings.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.contains(HotkeyID.maximize))
        XCTAssertTrue(ids.contains(HotkeyID.tileColumns))
        XCTAssertTrue(ids.contains(HotkeyID.switchSpace(1)))
        XCTAssertTrue(ids.contains(HotkeyID.moveSpace(1)))
    }

    func testCarbonModifierMasks() {
        XCTAssertEqual(
            HotkeyChordMapping.carbonModifiers(.optionOnly),
            UInt32(optionKey)
        )
        XCTAssertEqual(
            HotkeyChordMapping.carbonModifiers(.optionShift),
            UInt32(optionKey) | UInt32(shiftKey)
        )
        XCTAssertEqual(
            HotkeyChordMapping.carbonModifiers(.controlOption),
            UInt32(controlKey) | UInt32(optionKey)
        )
        let all = ModifierFlags(alt: true, shift: true, ctrl: true, cmd: true)
        XCTAssertEqual(
            HotkeyChordMapping.carbonModifiers(all),
            UInt32(optionKey) | UInt32(shiftKey) | UInt32(controlKey) | UInt32(cmdKey)
        )
    }

    func testDigitKeyCodes() {
        XCTAssertEqual(HotkeyChordMapping.digitKeyCode(1), UInt32(kVK_ANSI_1))
        XCTAssertEqual(HotkeyChordMapping.digitKeyCode(9), UInt32(kVK_ANSI_9))
        XCTAssertNil(HotkeyChordMapping.digitKeyCode(0))
        XCTAssertNil(HotkeyChordMapping.digitKeyCode(10))
    }

    func testLetterKeyCodes() {
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("a"), UInt32(kVK_ANSI_A))
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("f"), UInt32(kVK_ANSI_F))
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("z"), UInt32(kVK_ANSI_Z))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("1"))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("A"))
    }
}
