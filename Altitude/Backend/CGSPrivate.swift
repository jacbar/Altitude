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

    /// Spaces that contain `windowID`, including Spaces that are not visible.
    static func spaceIDs(forWindow windowID: CGWindowID) -> [CGSSpaceID] {
        let array = [NSNumber(value: windowID)] as CFArray
        guard let raw = CGSCopySpacesForWindows(connection, allSpacesMask, array) else { return [] }
        let numbers = raw as? [NSNumber] ?? []
        var seen = Set<CGSSpaceID>()
        var ids: [CGSSpaceID] = []
        for number in numbers where seen.insert(number.uint64Value).inserted {
            ids.append(number.uint64Value)
        }
        return ids
    }

    /// User, other, and currently visible Spaces. Matches the mask other Space tools pass here.
    private static let allSpacesMask: Int32 = 0x7
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

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windows: CFArray) -> CFArray?

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
