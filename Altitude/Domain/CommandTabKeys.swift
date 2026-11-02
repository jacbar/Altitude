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
    private static let tabKeyCode: Int64 = 48
    private static let escapeKeyCode: Int64 = 53
    private static let leftArrowKeyCode: Int64 = 123
    private static let rightArrowKeyCode: Int64 = 124
    private static let qKeyCode: Int64 = 12
    private static let hKeyCode: Int64 = 4

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
