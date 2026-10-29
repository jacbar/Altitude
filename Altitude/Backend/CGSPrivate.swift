import ApplicationServices
import CoreGraphics
import Foundation

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

/// Thin decls for undocumented SkyLight / CGS symbols.
/// These can break across macOS releases — keep call sites behind `SpaceService`.
enum CGSPrivate {
    static let connection: CGSConnectionID = CGSMainConnectionID()

    static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        guard let array = CGSCopyManagedDisplaySpaces(connection) else { return nil }
        return array as? [[String: Any]]
    }

    static func setCurrentSpace(displayIdentifier: String, spaceID: CGSSpaceID) {
        CGSManagedDisplaySetCurrentSpace(connection, displayIdentifier as CFString, spaceID)
    }

    static func moveWindowsToManagedSpace(windowIDs: [CGWindowID], spaceID: CGSSpaceID) {
        let windows = windowIDs.map { NSNumber(value: $0) } as NSArray
        // Prefer bridged WM operation on modern macOS; fall back to classic CGS.
        if SkyLightBridgedSPI.moveWindows(windowIDs, toSpace: spaceID) {
            return
        }
        CGSMoveWindowsToManagedSpace(connection, windows, spaceID)
    }

    static func activeSpaceID() -> CGSSpaceID {
        CGSGetActiveSpace(connection)
    }
}

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
func CGSManagedDisplaySetCurrentSpace(
    _ cid: CGSConnectionID,
    _ display: CFString,
    _ space: CGSSpaceID
)

@_silgen_name("CGSMoveWindowsToManagedSpace")
func CGSMoveWindowsToManagedSpace(
    _ cid: CGSConnectionID,
    _ windows: CFArray,
    _ space: CGSSpaceID
)

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
