import Foundation

/// Highest desktop number that should get an Option / Option+Shift digit hotkey.
/// Caps by configured `max_space`, live Space count (at least 1), and Carbon digits 1…9.
func effectiveMaxHotkeySpace(maxSpace: Int, spaceCount: Int) -> Int {
    min(maxSpace, max(spaceCount, 1), 9)
}
