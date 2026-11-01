import Foundation

enum DesktopFeature {
    /// Digit switch/move bindings when desktop is enabled; empty when disabled.
    static func bindings(config: AppConfig, spaceCount: Int) -> [HotkeyBinding] {
        guard config.desktop.enabled else { return [] }

        let maxN = effectiveMaxHotkeySpace(maxSpace: config.desktop.maxSpace, spaceCount: spaceCount)
        let switchMods = HotkeyChordMapping.carbonModifiers(config.desktop.switchModifiers)
        let moveMods = HotkeyChordMapping.carbonModifiers(config.desktop.moveModifiers)

        var result: [HotkeyBinding] = []
        for n in 1...maxN {
            guard let keyCode = HotkeyChordMapping.digitKeyCode(n) else { continue }
            result.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: switchMods,
                id: UInt32(n),
                action: .switchTo(n)
            ))
            result.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: moveMods,
                id: UInt32(100 + n),
                action: .moveTo(n)
            ))
        }
        return result
    }

    /// True only when desktop is enabled and `disable_motion` is set.
    static func instantSwitching(config: AppConfig) -> Bool {
        config.desktop.enabled && config.desktop.disableMotion
    }
}
