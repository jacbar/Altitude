import Carbon
import XCTest

final class HotkeyChordMappingTests: XCTestCase {
    func testCarbonModifiersMaskBits() {
        let all = ModifierFlags(alt: true, shift: true, ctrl: true, cmd: true)
        let mask = HotkeyChordMapping.carbonModifiers(all)
        XCTAssertEqual(mask & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(mask & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(mask & UInt32(optionKey), UInt32(optionKey))
        XCTAssertEqual(mask & UInt32(controlKey), UInt32(controlKey))

        let none = ModifierFlags(alt: false, shift: false, ctrl: false, cmd: false)
        XCTAssertEqual(HotkeyChordMapping.carbonModifiers(none), 0)
    }

    func testDigitKeyCodes() {
        XCTAssertEqual(HotkeyChordMapping.digitKeyCode(1), UInt32(kVK_ANSI_1))
        XCTAssertEqual(HotkeyChordMapping.digitKeyCode(9), UInt32(kVK_ANSI_9))
        XCTAssertNil(HotkeyChordMapping.digitKeyCode(0))
        XCTAssertNil(HotkeyChordMapping.digitKeyCode(10))
    }

    func testLetterKeyCodes() {
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("a"), UInt32(kVK_ANSI_A))
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("z"), UInt32(kVK_ANSI_Z))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("A"))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("1"))
    }
}
