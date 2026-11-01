import Foundation

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

/// Keeps `current` when `proposed` is empty or identical to `other`.
func validatedDesktopModifiers(
    current: ModifierFlags,
    other: ModifierFlags,
    proposed: ModifierFlags
) -> ModifierFlags {
    guard proposed.hasAny, proposed != other else { return current }
    return proposed
}

/// Keeps `current` when the key is not a…z, there are no modifiers, or the chord matches `other`.
func validatedWindowChord(
    current: KeyChord,
    other: KeyChord,
    proposed: KeyChord
) -> KeyChord {
    guard let lower = proposed.key.lowercased().first,
          ("a"..."z").contains(lower),
          proposed.modifiers.hasAny
    else {
        return current
    }
    let normalized = KeyChord(modifiers: proposed.modifiers, key: lower)
    guard normalized != other else { return current }
    return normalized
}
