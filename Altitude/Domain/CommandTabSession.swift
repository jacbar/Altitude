import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum CommandTabKeyAction: Equatable, Sendable {
    case move(Int)
    case cancel
    case commit
    case quit
    case hide
    case drop
}

/// Pure Command-Tab selection state and key mapping.
struct CommandTabSession<Target>: Sendable where Target: Sendable {
    var targets: [Target]
    var index: Int

    mutating func move(by delta: Int) {
        let count = targets.count
        guard count > 0, delta != 0 else { return }
        index = (index + delta % count + count) % count
    }
}

/// Maps a switcher key while a session is open.
func commandTabKeyAction(keyCode: Int64, flags: CGEventFlags) -> CommandTabKeyAction {
    if keyCode == Int64(kVK_Escape) {
        return .cancel
    }
    // Same outcome as a missed Command-up: ending the session by committing.
    if !flags.contains(.maskCommand) {
        return .commit
    }

    let shift = flags.contains(.maskShift)
    let extra = flags.contains(.maskAlternate) || flags.contains(.maskControl)

    switch keyCode {
    case Int64(kVK_LeftArrow):
        return .move(-1)
    case Int64(kVK_RightArrow):
        return .move(1)
    case Int64(kVK_Tab) where !extra:
        return .move(shift ? -1 : 1)
    case Int64(kVK_ANSI_Q) where !extra:
        return .quit
    case Int64(kVK_ANSI_H) where !extra:
        return .hide
    default:
        return .drop
    }
}
