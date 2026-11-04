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

/// Accepts a…z with modifiers that do not collide with window or sibling app-shortcut chords.
/// Desktop digit bindings cannot collide with letter chords.
func validatedAppShortcutChord(
    proposed: KeyChord,
    conflicting: [KeyChord]
) -> ShortcutValidationResult<KeyChord> {
    guard let lower = proposed.key.lowercased().first,
          ("a"..."z").contains(lower),
          proposed.modifiers.hasAny
    else {
        return .invalid
    }
    let normalized = KeyChord(modifiers: proposed.modifiers, key: lower)
    if conflicting.contains(normalized) {
        return .conflict
    }
    return .accepted(normalized)
}
