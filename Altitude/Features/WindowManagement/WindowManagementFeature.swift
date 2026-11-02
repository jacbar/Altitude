import Foundation

enum WindowManagementFeature {
    /// Maximize and equal-split chords when window management is enabled; empty when disabled.
    static func bindings(config: AppConfig) -> [HotkeyBinding] {
        guard config.windowManagement.enabled else { return [] }

        var result: [HotkeyBinding] = []
        let maximize = config.windowManagement.maximize
        if let keyCode = HotkeyChordMapping.letterKeyCode(maximize.key) {
            result.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: HotkeyChordMapping.carbonModifiers(maximize.modifiers),
                id: HotkeyID.maximize,
                action: .maximizeAll
            ))
        }
        let equalSplit = config.windowManagement.equalSplit
        if let keyCode = HotkeyChordMapping.letterKeyCode(equalSplit.key) {
            result.append(HotkeyBinding(
                keyCode: keyCode,
                modifiers: HotkeyChordMapping.carbonModifiers(equalSplit.modifiers),
                id: HotkeyID.equalSplit,
                action: .tileColumns
            ))
        }
        return result
    }

    static func margin(config: AppConfig) -> Int {
        config.windowManagement.margin
    }
}
