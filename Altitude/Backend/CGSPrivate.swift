import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

typealias CGSConnectionID = Int32

/// Thin wrappers for undocumented SkyLight / CGS symbols resolved via `dlsym`.
/// These can break across macOS releases — keep call sites behind `SpaceService`.
/// Missing symbols fail soft (nil / no-op / empty) instead of crashing at launch.
enum CGSPrivate {
    // Resolved once at first use; dlopen handles are process-global.
    nonisolated(unsafe) private static let skyLightHandle: UnsafeMutableRawPointer? = {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ) {
            return handle
        }
        return dlopen(nil, RTLD_LAZY)
    }()

    private typealias MainConnectionIDFn = @convention(c) () -> CGSConnectionID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    private typealias MoveWindowsToManagedSpaceFn = @convention(c) (CGSConnectionID, CFArray, CGSSpaceID) -> Void
    private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> CGSSpaceID
    private typealias CopySpacesForWindowsFn = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let mainConnectionIDFn: MainConnectionIDFn? = {
        guard let handle = skyLightHandle,
              let symbol = dlsym(handle, "CGSMainConnectionID")
        else { return nil }
        return unsafeBitCast(symbol, to: MainConnectionIDFn.self)
    }()

    private static let copyManagedDisplaySpacesFn: CopyManagedDisplaySpacesFn? = {
        guard let handle = skyLightHandle,
              let symbol = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return unsafeBitCast(symbol, to: CopyManagedDisplaySpacesFn.self)
    }()

    private static let moveWindowsToManagedSpaceFn: MoveWindowsToManagedSpaceFn? = {
        guard let handle = skyLightHandle,
              let symbol = dlsym(handle, "CGSMoveWindowsToManagedSpace")
        else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsToManagedSpaceFn.self)
    }()

    private static let getActiveSpaceFn: GetActiveSpaceFn? = {
        guard let handle = skyLightHandle,
              let symbol = dlsym(handle, "CGSGetActiveSpace")
        else { return nil }
        return unsafeBitCast(symbol, to: GetActiveSpaceFn.self)
    }()

    private static let copySpacesForWindowsFn: CopySpacesForWindowsFn? = {
        guard let handle = skyLightHandle,
              let symbol = dlsym(handle, "CGSCopySpacesForWindows")
        else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesForWindowsFn.self)
    }()

    static let connection: CGSConnectionID = mainConnectionIDFn?() ?? 0

    static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        guard connection != 0,
              let fn = copyManagedDisplaySpacesFn,
              let unmanaged = fn(connection)
        else { return nil }
        let array = unmanaged.takeRetainedValue()
        return array as? [[String: Any]]
    }

    static func moveWindowsToManagedSpace(windowIDs: [CGWindowID], spaceID: CGSSpaceID) {
        guard connection != 0 else { return }
        let windows = windowIDs.map { NSNumber(value: $0) } as NSArray
        // Prefer bridged WM operation on modern macOS; fall back to classic CGS.
        if SkyLightBridgedSPI.moveWindows(windowIDs, toSpace: spaceID) {
            return
        }
        moveWindowsToManagedSpaceFn?(connection, windows, spaceID)
    }

    static func activeSpaceID() -> CGSSpaceID {
        guard connection != 0 else { return 0 }
        return getActiveSpaceFn?(connection) ?? 0
    }

    /// Spaces that contain `windowID`, including Spaces that are not visible.
    static func spaceIDs(forWindow windowID: CGWindowID) -> [CGSSpaceID] {
        guard connection != 0 else { return [] }
        let array = [NSNumber(value: windowID)] as CFArray
        guard let fn = copySpacesForWindowsFn,
              let unmanaged = fn(connection, allSpacesMask, array)
        else { return [] }
        let raw = unmanaged.takeRetainedValue()
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
