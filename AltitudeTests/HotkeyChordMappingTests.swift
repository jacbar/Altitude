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

    func testLetterKeyCodesUsesResolver() {
        let nonUSA = UInt32(kVK_ANSI_A) &+ 1
        XCTAssertNotEqual(nonUSA, UInt32(kVK_ANSI_A))

        struct FakeResolver: LetterKeyResolving {
            let aCode: UInt32
            func keyCode(for letter: Character) -> UInt32? {
                switch letter {
                case "a": return aCode
                case "q": return nil
                default: return nil
                }
            }
        }

        let resolver = FakeResolver(aCode: nonUSA)
        XCTAssertEqual(HotkeyChordMapping.letterKeyCode("a", resolver: resolver), nonUSA)
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("q", resolver: resolver))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("A", resolver: resolver))
        XCTAssertNil(HotkeyChordMapping.letterKeyCode("1", resolver: resolver))
    }
}
