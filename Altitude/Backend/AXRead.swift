import ApplicationServices
import CoreGraphics
import Foundation

/// Shared Accessibility attribute reads. Empty string / false / nil / 0 on failure.
enum AXRead {
    static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return ""
        }
        return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? Bool) ?? false
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var size = CGSize.zero
        let axValue = unsafeBitCast(ref, to: AXValue.self)
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    static func position(_ element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        let axValue = unsafeBitCast(ref, to: AXValue.self)
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success else { return 0 }
        return id
    }
}
