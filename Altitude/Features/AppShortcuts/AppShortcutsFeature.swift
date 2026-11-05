import Foundation

enum AppShortcutsFeature {
    /// Letter/digit-chord bindings for configured app jumps; empty when the module is off.
    static func bindings(config: AppConfig) -> [HotkeyBinding] {
        guard config.appShortcuts.enabled else { return [] }

        var result: [HotkeyBinding] = []
        for (index, entry) in config.appShortcuts.entries.enumerated() {
            guard !entry.bundleID.isEmpty,
                  let keyCode = HotkeyChordMapping.chordKeyCode(entry.chord.key)
            else {
                continue
            }
            result.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: HotkeyChordMapping.carbonModifiers(entry.chord.modifiers),
                id: HotkeyID.appShortcut(index),
                action: .jumpToApp(index)
            ))
        }
        return result
    }
}
