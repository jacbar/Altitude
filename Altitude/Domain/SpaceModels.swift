import AppKit
import CoreGraphics
import Foundation

struct DesktopSpace: Identifiable, Hashable, Sendable {
    /// 1-based index in the flattened user-desktop list (Mission Control order, v1).
    let index: Int
    let id: CGSSpaceID
    let displayIdentifier: String
    let uuid: String?
    let isCurrent: Bool
}

struct SpaceSnapshot: Sendable {
    let spaces: [DesktopSpace]
    let currentIndex: Int?

    static let empty = SpaceSnapshot(spaces: [], currentIndex: nil)
}

enum SpaceServiceError: Error, LocalizedError {
    case spacesUnavailable
    case invalidSpaceIndex(Int)
    case crossDisplaySwitch(Int)
    case noFocusedWindow
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .spacesUnavailable:
            return "Unable to read macOS Spaces (SkyLight unavailable)"
        case .invalidSpaceIndex(let index):
            return "No desktop at index \(index)"
        case .crossDisplaySwitch(let index):
            return "Desktop \(index) is on another display; switching across displays is not supported"
        case .noFocusedWindow:
            return "No focused window to move"
        case .accessibilityDenied:
            return "Accessibility permission is required"
        }
    }
}

enum InstantSwitchResult: Sendable {
    /// The target is already the current Space, or there is nothing to move toward.
    case alreadyThere
    /// An instant dock-swipe was posted and has not settled yet.
    case posted(steps: Int)
    /// Every candidate Space is on another display.
    case otherDisplay
    case unavailable
}

enum SpaceHopDirection: Sendable {
    case previous
    case next
}

protocol SpaceService: AnyObject {
    /// Skip the paced trackpad-like slide and jump through Spaces as fast as the Dock allows.
    var instantSwitching: Bool { get set }
    func snapshot() -> SpaceSnapshot
    func switchTo(index: Int) throws
    func moveFocusedWindow(to index: Int) throws
    /// Jump the active display to the closest candidate Space with no slide.
    func switchInstantly(toPreferredSpaceAmong spaceIDs: [CGSSpaceID]) -> InstantSwitchResult
    /// Move one Space on the active display with no slide. At the first/last Space, returns `.alreadyThere` and posts nothing.
    func moveOneSpaceInstantly(direction: SpaceHopDirection) -> InstantSwitchResult
    /// Call when macOS reports an active-space change (trackpad, Mission Control, etc.).
    func acknowledgeSystemSpaceChange()
    /// Current Space on `screen`, preferring an in-flight swipe prediction when it applies.
    func currentSpaceID(on screen: NSScreen) -> CGSSpaceID?
}
