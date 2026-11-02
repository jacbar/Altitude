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
        let value = unsafeBitCast(ref, to: AXValue.self)
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
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
        let value = unsafeBitCast(ref, to: AXValue.self)
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    func axWindowID() -> CGWindowID {
        AXUIElementGetWindow.windowID(of: self) ?? 0
    }
}
