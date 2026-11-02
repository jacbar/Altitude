import ApplicationServices
import CoreGraphics
import Foundation

extension AXUIElement {
    func axString(_ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &ref) == .success else {
            return ""
        }
        return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func axBool(_ attribute: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? Bool) ?? false
    }

    func axSize() -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    func axPosition() -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(ref as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    func axWindowID() -> CGWindowID {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success else { return 0 }
        return id
    }
}
