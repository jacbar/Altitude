import ApplicationServices
import CoreGraphics
import Foundation
import os.log

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

private let cgsLog = Logger(subsystem: "com.altitude.app", category: "CGS")

/// Thin wrappers for undocumented SkyLight / CGS symbols resolved via dlsym.
/// These can break across macOS releases — keep call sites behind `SpaceService`.
enum CGSPrivate {
    static let connection: CGSConnectionID = AltitudeCGSMainConnectionID()

    static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        guard let array = AltitudeCGSCopyManagedDisplaySpaces(connection) else { return nil }
        return array as? [[String: Any]]
    }

    static func moveWindowsToManagedSpace(windowIDs: [CGWindowID], spaceID: CGSSpaceID) {
        let windows = windowIDs.map { NSNumber(value: $0) } as NSArray
        // Prefer bridged WM operation on modern macOS; fall back to classic CGS.
        if SkyLightBridgedSPI.moveWindows(windowIDs, toSpace: spaceID) {
            return
        }
        if !AltitudeCGSMoveWindowsToManagedSpace(connection, windows, spaceID) {
            cgsLog.error("CGSMoveWindowsToManagedSpace unavailable")
            return
        }
    }

    static func activeSpaceID() -> CGSSpaceID {
        AltitudeCGSGetActiveSpace(connection)
    }

    /// Spaces that contain `windowID`, including Spaces that are not visible.
    static func spaceIDs(forWindow windowID: CGWindowID) -> [CGSSpaceID] {
        let array = [NSNumber(value: windowID)] as CFArray
        guard let raw = AltitudeCGSCopySpacesForWindows(connection, allSpacesMask, array) else { return [] }
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

func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError {
    AltitudeAXUIElementGetWindow(element, windowID)
}
