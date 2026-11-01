import XCTest
@testable import Altitude

final class ShortcutEditingTests: XCTestCase {
    func testShortcutSymbolsAppleOrder() {
        let all = ModifierFlags(alt: true, shift: true, ctrl: true, cmd: true)
        XCTAssertEqual(shortcutSymbols(modifiers: all, key: "f"), "⌃⌥⇧⌘F")
        XCTAssertEqual(
            shortcutSymbols(modifiers: .controlOption, key: "a"),
            "⌃⌥A"
        )
        XCTAssertEqual(
            shortcutSymbols(modifiers: .optionShift, key: nil),
            "⌥⇧"
        )
        XCTAssertEqual(
            shortcutSymbols(modifiers: .optionOnly, key: "z"),
            "⌥Z"
        )
    }

    func testValidatedDesktopModifiersAcceptsDistinctSet() {
        let current = ModifierFlags.optionOnly
        let other = ModifierFlags.optionShift
        let proposed = ModifierFlags(alt: false, shift: false, ctrl: true, cmd: false)
        XCTAssertEqual(
            validatedDesktopModifiers(current: current, other: other, proposed: proposed),
            proposed
        )
    }

    func testValidatedDesktopModifiersRejectsEmpty() {
        let current = ModifierFlags.optionOnly
        let other = ModifierFlags.optionShift
        let empty = ModifierFlags(alt: false, shift: false, ctrl: false, cmd: false)
        XCTAssertEqual(
            validatedDesktopModifiers(current: current, other: other, proposed: empty),
            current
        )
    }

    func testValidatedDesktopModifiersRejectsIdentical() {
        let current = ModifierFlags.optionOnly
        let other = ModifierFlags.optionShift
        XCTAssertEqual(
            validatedDesktopModifiers(current: current, other: other, proposed: other),
            current
        )
    }

    func testValidatedWindowChordRejectsNonLetter() {
        let current = KeyChord.maximizeDefault
        let other = KeyChord.equalSplitDefault
        let proposed = KeyChord(modifiers: .controlOption, key: "1")
        XCTAssertEqual(
            validatedWindowChord(current: current, other: other, proposed: proposed),
            current
        )
    }

    func testValidatedWindowChordRejectsModifierFree() {
        let current = KeyChord.maximizeDefault
        let other = KeyChord.equalSplitDefault
        let none = ModifierFlags(alt: false, shift: false, ctrl: false, cmd: false)
        let proposed = KeyChord(modifiers: none, key: "f")
        XCTAssertEqual(
            validatedWindowChord(current: current, other: other, proposed: proposed),
            current
        )
    }

    func testValidatedWindowChordRejectsDuplicate() {
        let current = KeyChord.maximizeDefault
        let other = KeyChord.equalSplitDefault
        XCTAssertEqual(
            validatedWindowChord(current: current, other: other, proposed: other),
            current
        )
    }

    func testValidatedWindowChordAcceptsDistinctLetter() {
        let current = KeyChord.maximizeDefault
        let other = KeyChord.equalSplitDefault
        let proposed = KeyChord(modifiers: .controlOption, key: "X")
        XCTAssertEqual(
            validatedWindowChord(current: current, other: other, proposed: proposed),
            KeyChord(modifiers: .controlOption, key: "x")
        )
    }
}
