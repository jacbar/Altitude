@preconcurrency import ApplicationServices
@preconcurrency import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "FocusedWindow")

/// Resolves the focused window's `CGWindowID` via Accessibility.
final class FocusedWindowResolver: @unchecked Sendable {
    /// Keep focused-window lookups short so a hung app cannot stall Space hops.
    private let axTimeoutSeconds: Float = 0.1

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt. Call only from an explicit user action
    /// (or a one-time first-run bootstrap), never on every launch.
    @discardableResult
    func promptForAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func focusedWindowID() -> CGWindowID? {
        guard isAccessibilityTrusted else {
            log.error("Accessibility not trusted")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, axTimeoutSeconds)
        var focusedAppObject: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppObject
        )
        guard appStatus == .success, let focusedAppObject else {
            // Fall back to frontmost app from NSWorkspace.
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return focusedWindowID(forPID: app.processIdentifier)
        }

        let focusedApp = unsafeBitCast(focusedAppObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focusedApp, axTimeoutSeconds)
        return focusedWindowID(fromAppElement: focusedApp)
    }

    private func focusedWindowID(forPID pid: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeoutSeconds)
        return focusedWindowID(fromAppElement: appElement)
    }

    private func focusedWindowID(fromAppElement app: AXUIElement) -> CGWindowID? {
        var focusedWindowObject: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowObject
        )
        guard status == .success, let focusedWindowObject else {
            log.info("No focused window on frontmost app")
            return nil
        }

        let window = unsafeBitCast(focusedWindowObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, axTimeoutSeconds)
        guard let windowID = AXUIElementGetWindow.windowID(of: window) else {
            log.error("_AXUIElementGetWindow unavailable or failed")
            return nil
        }
        return windowID
    }
}
