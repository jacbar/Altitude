import Foundation

/// Modifier combination for a hotkey chord.
struct ModifierFlags: Equatable, Sendable {
    var alt: Bool
    var shift: Bool
    var ctrl: Bool
    var cmd: Bool

    var hasAny: Bool { alt || shift || ctrl || cmd }

    static let optionOnly = ModifierFlags(alt: true, shift: false, ctrl: false, cmd: false)
    static let optionShift = ModifierFlags(alt: true, shift: true, ctrl: false, cmd: false)
    static let controlOption = ModifierFlags(alt: true, shift: false, ctrl: true, cmd: false)
}

/// Parsed modifiers where `nil` means the flag was absent from config.
struct PartialModifierFlags: Equatable, Sendable {
    var alt: Bool?
    var shift: Bool?
    var ctrl: Bool?
    var cmd: Bool?

    func resolved(defaults: ModifierFlags) -> ModifierFlags {
        ModifierFlags(
            alt: alt ?? defaults.alt,
            shift: shift ?? defaults.shift,
            ctrl: ctrl ?? defaults.ctrl,
            cmd: cmd ?? defaults.cmd
        )
    }
}

/// A letter key plus modifiers (window-management chords).
struct KeyChord: Equatable, Sendable {
    var modifiers: ModifierFlags
    /// Lowercase ASCII letter `a`…`z`.
    var key: Character

    static let maximizeDefault = KeyChord(modifiers: .controlOption, key: "f")
    static let equalSplitDefault = KeyChord(modifiers: .controlOption, key: "a")
}

/// Partial window chord; `nil` key means missing / empty / invalid.
struct PartialKeyChord: Equatable, Sendable {
    var modifiers: PartialModifierFlags
    var key: Character?
}

struct DesktopShortcutResolution: Equatable, Sendable {
    var switchModifiers: ModifierFlags
    var moveModifiers: ModifierFlags
    var usedFallback: Bool
}

struct WindowChordResolution: Equatable, Sendable {
    var maximize: KeyChord
    var equalSplit: KeyChord
    var usedFallback: Bool
}

/// Resolves desktop switch/move modifier sets.
/// A missing modifier flag keeps that flag's default. If either resolved set has no
/// modifiers, or the sets are equal, both become Option and Option+Shift.
func resolveDesktopShortcuts(
    switch switchPartial: PartialModifierFlags,
    move movePartial: PartialModifierFlags
) -> DesktopShortcutResolution {
    let resolvedSwitch = switchPartial.resolved(defaults: .optionOnly)
    let resolvedMove = movePartial.resolved(defaults: .optionShift)
    if !resolvedSwitch.hasAny || !resolvedMove.hasAny || resolvedSwitch == resolvedMove {
        return DesktopShortcutResolution(
            switchModifiers: .optionOnly,
            moveModifiers: .optionShift,
            usedFallback: true
        )
    }
    return DesktopShortcutResolution(
        switchModifiers: resolvedSwitch,
        moveModifiers: resolvedMove,
        usedFallback: false
    )
}

/// Resolves window maximize / equal-split chords.
/// A missing modifier keeps that chord's default. Missing, empty, or non-letter key
/// becomes that chord's default key. If the two resolved chords are equal, both become
/// Control+Option+F and Control+Option+A.
func resolveWindowChords(
    maximize maximizePartial: PartialKeyChord,
    equalSplit equalSplitPartial: PartialKeyChord
) -> WindowChordResolution {
    let maximizeDefaults = KeyChord.maximizeDefault
    let equalSplitDefaults = KeyChord.equalSplitDefault

    let maximize = KeyChord(
        modifiers: maximizePartial.modifiers.resolved(defaults: maximizeDefaults.modifiers),
        key: maximizePartial.key ?? maximizeDefaults.key
    )
    let equalSplit = KeyChord(
        modifiers: equalSplitPartial.modifiers.resolved(defaults: equalSplitDefaults.modifiers),
        key: equalSplitPartial.key ?? equalSplitDefaults.key
    )

    if maximize == equalSplit {
        return WindowChordResolution(
            maximize: maximizeDefaults,
            equalSplit: equalSplitDefaults,
            usedFallback: true
        )
    }
    return WindowChordResolution(
        maximize: maximize,
        equalSplit: equalSplit,
        usedFallback: false
    )
}
