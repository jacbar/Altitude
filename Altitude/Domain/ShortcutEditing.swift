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
func validatedDesktopModifiers(
    other: ModifierFlags,
    proposed: ModifierFlags
) -> ShortcutValidationResult<ModifierFlags> {
    guard proposed.hasAny else { return .invalid }
    guard proposed != other else { return .conflict }
    return .accepted(proposed)
}

/// Accepts a…z with modifiers that differ from `other`; otherwise invalid or conflict.
func validatedWindowChord(
    other: KeyChord,
    proposed: KeyChord
) -> ShortcutValidationResult<KeyChord> {
    guard let lower = proposed.key.lowercased().first,
          ("a"..."z").contains(lower),
          proposed.modifiers.hasAny
    else {
        return .invalid
    }
    let normalized = KeyChord(modifiers: proposed.modifiers, key: lower)
    guard normalized != other else { return .conflict }
    return .accepted(normalized)
}
