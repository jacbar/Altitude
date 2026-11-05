import Foundation

/// Outcome of validating a proposed shortcut against its same-tab sibling.
enum ShortcutValidationResult<Value: Equatable>: Equatable {
    case accepted(Value)
    case conflict
    case invalid
}

/// Apple-order chord string: ⌃ ⌥ ⇧ ⌘, then the uppercase letter when present.
func shortcutSymbols(modifiers: ModifierFlags, key: Character?) -> String {
    var parts: [String] = []
    if modifiers.ctrl { parts.append("⌃") }
    if modifiers.alt { parts.append("⌥") }
    if modifiers.shift { parts.append("⇧") }
    if modifiers.cmd { parts.append("⌘") }
    if let key {
        parts.append(String(key).uppercased())
    }
    return parts.joined()
}

/// Accepts a non-empty set that differs from `other`; empty is invalid, match is conflict.
/// Callers keep the prior value on `.invalid` / `.conflict`.
func validatedDesktopModifiers(
    other: ModifierFlags,
    proposed: ModifierFlags
) -> ShortcutValidationResult<ModifierFlags> {
    guard proposed.hasAny else { return .invalid }
    guard proposed != other else { return .conflict }
    return .accepted(proposed)
}

/// Accepts a…z with modifiers that differ from `other` and `additionalConflicts`.
/// Callers keep the prior value on `.invalid` / `.conflict`.
/// Desktop digit bindings cannot collide with letter chords, so they are not listed here.
func validatedWindowChord(
    other: KeyChord,
    proposed: KeyChord,
    additionalConflicts: [KeyChord] = []
) -> ShortcutValidationResult<KeyChord> {
    guard let lower = proposed.key.lowercased().first,
          ("a"..."z").contains(lower),
          proposed.modifiers.hasAny
    else {
        return .invalid
    }
    let normalized = KeyChord(modifiers: proposed.modifiers, key: lower)
    if normalized == other || additionalConflicts.contains(normalized) {
        return .conflict
    }
    return .accepted(normalized)
}

/// Accepts a…z or 0…9 with modifiers that do not collide with window, sibling, or Desktop digit chords.
func validatedAppShortcutChord(
    proposed: KeyChord,
    conflicting: [KeyChord],
    desktopSwitch: ModifierFlags = .optionOnly,
    desktopMove: ModifierFlags = .optionShift
) -> ShortcutValidationResult<KeyChord> {
    guard let raw = proposed.key.lowercased().first,
          (("a"..."z").contains(raw) || ("0"..."9").contains(raw)),
          proposed.modifiers.hasAny
    else {
        return .invalid
    }
    let normalized = KeyChord(modifiers: proposed.modifiers, key: raw)
    if conflicting.contains(normalized) {
        return .conflict
    }
    // Desktop registers switch/move + digits 1…9; same modifiers + digit is a Carbon conflict.
    if ("1"..."9").contains(raw),
       normalized.modifiers == desktopSwitch || normalized.modifiers == desktopMove
    {
        return .conflict
    }
    return .accepted(normalized)
}
