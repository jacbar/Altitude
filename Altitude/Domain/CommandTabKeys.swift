import Carbon
import Foundation

enum CommandTabSwitcherAction: Equatable {
    case move(Int)
    case cancel
    case commit
    case quit
    case hide
    case swallow
}

enum CommandTabKeys {
    private static let tabKeyCode: Int64 = Int64(kVK_Tab)
    private static let escapeKeyCode: Int64 = Int64(kVK_Escape)
    private static let leftArrowKeyCode: Int64 = Int64(kVK_LeftArrow)
    private static let rightArrowKeyCode: Int64 = Int64(kVK_RightArrow)
    private static let qKeyCode: Int64 = Int64(kVK_ANSI_Q)
    private static let hKeyCode: Int64 = Int64(kVK_ANSI_H)

    /// Pure key → action map for an open Command-Tab session.
    static func action(
        keyCode: Int64,
        command: Bool,
        shift: Bool,
        alternate: Bool,
        control: Bool,
        isKeyDown: Bool,
        isRepeat: Bool
    ) -> CommandTabSwitcherAction {
        let press = isKeyDown && !isRepeat

        if keyCode == leftArrowKeyCode {
            return press ? .move(-1) : .swallow
        }
        if keyCode == rightArrowKeyCode {
            return press ? .move(1) : .swallow
        }

        if keyCode == escapeKeyCode {
            return press ? .cancel : .swallow
        }

        if !command {
            return .commit
        }

        if alternate || control {
            return .swallow
        }

        if keyCode == tabKeyCode {
            return press ? .move(shift ? -1 : 1) : .swallow
        }
        if keyCode == qKeyCode {
            return press ? .quit : .swallow
        }
        if keyCode == hKeyCode {
            return press ? .hide : .swallow
        }

        return .swallow
    }
}
