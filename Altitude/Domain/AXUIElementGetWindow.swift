import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

/// Resolves the private `_AXUIElementGetWindow` symbol via `dlsym`.
/// Missing symbol fails soft — callers treat it as no window id.
enum AXUIElementGetWindow {
    private typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // Resolved once at first use; missing symbol stays nil for soft failure.
    private static let resolved: Fn? = {
        let handles: [UnsafeMutableRawPointer?] = [
            dlopen(nil, RTLD_LAZY),
            dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
        ]
        for handle in handles {
            guard let handle,
                  let symbol = dlsym(handle, "_AXUIElementGetWindow")
            else { continue }
            return unsafeBitCast(symbol, to: Fn.self)
        }
        return nil
    }()

    /// Returns the window id, or `nil` when the symbol is missing or the call fails.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = resolved else { return nil }
        var id: CGWindowID = 0
        guard fn(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
