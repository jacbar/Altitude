import Foundation

enum HotkeyID {
    static func switchDesktop(_ n: Int) -> UInt32 { UInt32(n) } // 1...9
    static func moveDesktop(_ n: Int) -> UInt32 { UInt32(100 + n) } // 101...109
    static let maximize: UInt32 = 200
    static let equalSplit: UInt32 = 201
    /// App Shortcuts entries: `300 + index` (0-based into `appShortcuts.entries`).
    static func appShortcut(_ n: Int) -> UInt32 { UInt32(300 + n) } // 300...331
}
