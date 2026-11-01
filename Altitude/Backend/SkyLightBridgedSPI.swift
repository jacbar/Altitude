import CoreGraphics
import Darwin
import Foundation
import ObjectiveC

/// macOS 14+ window-management bridge used by apps like Loop / WindowKit.
/// Moves windows across Spaces without partially disabling SIP.
enum SkyLightBridgedSPI {
    private static let objcMessageSend: UnsafeMutableRawPointer? = {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        return dlsym(handle, "objc_msgSend")
    }()

    private enum PerformOutcome {
        case object(AnyObject?)
        case bool(Bool)
        case void
    }

    /// Returns `false` when the bridge is unavailable or reports failure, so callers can fall back.
    static func moveWindows(_ windowIDs: [CGWindowID], toSpace spaceID: CGSSpaceID) -> Bool {
        guard let operation = makeMoveWindowsOperation(windowIDs: windowIDs, spaceID: spaceID),
              let outcome = performWithWMBridgeDelegate(operation)
        else {
            return false
        }
        if case .bool(let succeeded) = outcome {
            return succeeded
        }
        return true
    }

    static func copyManagedDisplaySpaces() -> [NSDictionary]? {
        guard let operationClass = NSClassFromString("SLSBridgedCopyManagedDisplaySpacesOperation") as? NSObject.Type else {
            return nil
        }
        let operation = operationClass.init()
        guard let outcome = performWithWMBridgeDelegate(operation) else { return nil }

        if case .object(let result?) = outcome, let list = propertyListArray(of: result) {
            return list
        }
        return propertyListArray(of: operation)
    }

    private static func propertyListArray(of object: AnyObject) -> [NSDictionary]? {
        guard let object = object as? NSObject,
              object.responds(to: NSSelectorFromString("propertyListArray"))
        else {
            return nil
        }
        return object.value(forKey: "propertyListArray") as? [NSDictionary]
    }

    /// The selector is private, so its return type is read from the runtime rather than assumed;
    /// treating a `BOOL`/`void` return as an object would retain a garbage pointer.
    private static func performWithWMBridgeDelegate(_ operation: NSObject) -> PerformOutcome? {
        guard let objcMessageSend,
              let operationClass = object_getClass(operation)
        else {
            return nil
        }
        let selector = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let method = class_getInstanceMethod(operationClass, selector),
              let returnType = returnTypeEncoding(of: method)
        else {
            return nil
        }

        switch returnType {
        case "@":
            typealias Perform = @convention(c) (NSObject, Selector) -> UnsafeRawPointer?
            let result = unsafeBitCast(objcMessageSend, to: Perform.self)(operation, selector)
            return .object(result.map { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() })
        case "B":
            typealias Perform = @convention(c) (NSObject, Selector) -> Bool
            return .bool(unsafeBitCast(objcMessageSend, to: Perform.self)(operation, selector))
        case "c":
            typealias Perform = @convention(c) (NSObject, Selector) -> Int8
            return .bool(unsafeBitCast(objcMessageSend, to: Perform.self)(operation, selector) != 0)
        case "v":
            typealias Perform = @convention(c) (NSObject, Selector) -> Void
            unsafeBitCast(objcMessageSend, to: Perform.self)(operation, selector)
            return .void
        default:
            return nil
        }
    }

    private static func returnTypeEncoding(of method: Method) -> Character? {
        let raw = method_copyReturnType(method)
        defer { free(raw) }
        let typeQualifiers: Set<Character> = ["r", "n", "N", "o", "O", "R", "V", "A"]
        return String(cString: raw).first { !typeQualifiers.contains($0) }
    }

    /// `alloc` returns +1 and `init…` consumes it and returns +1, so both go through raw
    /// pointers and only the initialized result is taken as retained.
    private static func makeMoveWindowsOperation(
        windowIDs: [CGWindowID],
        spaceID: CGSSpaceID
    ) -> NSObject? {
        guard let objcMessageSend,
              let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") as? NSObject.Type
        else {
            return nil
        }

        let initializer = NSSelectorFromString("initWithWindows:spaceID:")
        guard operationClass.instancesRespond(to: initializer) else { return nil }

        typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeRawPointer?
        let allocate = unsafeBitCast(objcMessageSend, to: Allocate.self)
        guard let allocated = allocate(operationClass, NSSelectorFromString("alloc")) else { return nil }

        let windows = windowIDs.map { NSNumber(value: $0) } as NSArray
        typealias InitMove = @convention(c) (UnsafeRawPointer, Selector, NSArray, UInt64) -> UnsafeRawPointer?
        let initMove = unsafeBitCast(objcMessageSend, to: InitMove.self)
        guard let initialized = initMove(allocated, initializer, windows, spaceID) else { return nil }
        return Unmanaged<NSObject>.fromOpaque(initialized).takeRetainedValue()
    }
}
