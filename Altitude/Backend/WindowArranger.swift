import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "WindowArranger")

enum ArrangeAction {
    case maximize
    case columns
}

enum ArrangeResult: Equatable {
    case applied(Int)
    case accessibilityDenied
    case nothingToDo
}

/// Resizes included windows on one Space via Accessibility. Does not beep, focus, or change z-order.
final class WindowArranger {
    private static let axTimeoutSeconds: Float = 0.25
    private static let standardWindowSubrole = "AXStandardWindow"
    private static let fullScreenAttribute = "AXFullScreen"

    func arrange(
        _ action: ArrangeAction,
        margin: Int,
        on spaceID: CGSSpaceID,
        screen: NSScreen
    ) -> ArrangeResult {
        guard AXIsProcessTrusted() else { return .accessibilityDenied }

        let candidates = collectWindows(on: spaceID)
        guard !candidates.isEmpty else { return .nothingToDo }

        let order = WindowArrangement.sortIndices(
            left: candidates.map(\.position.x),
            top: candidates.map(\.position.y)
        )
        let sorted = order.map { candidates[$0] }

        let visible = screen.visibleFrame
        let marginCG = CGFloat(margin)
        let targets: [CGRect]
        switch action {
        case .maximize:
            guard let rect = WindowArrangement.maximizedRect(visibleFrame: visible, margin: marginCG) else {
                return .nothingToDo
            }
            targets = Array(repeating: rect, count: sorted.count)
        case .columns:
            guard let rects = WindowArrangement.columnRects(
                visibleFrame: visible,
                margin: marginCG,
                count: sorted.count
            ) else {
                return .nothingToDo
            }
            targets = rects
        }

        guard let primaryMaxY = NSScreen.screens.map(\.frame.maxY).max() else {
            return .nothingToDo
        }

        var applied = 0
        for (window, rect) in zip(sorted, targets) {
            if setFrame(window.element, to: rect, primaryMaxY: primaryMaxY) {
                applied += 1
            }
        }
        return applied == 0 ? .nothingToDo : .applied(applied)
    }

    private struct Candidate {
        let element: AXUIElement
        let position: CGPoint
    }

    private func collectWindows(on spaceID: CGSSpaceID) -> [Candidate] {
        let selfBundle = Bundle.main.bundleIdentifier
        var results: [Candidate] = []

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isHidden,
                  !app.isTerminated,
                  app.bundleIdentifier != selfBundle
            else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            ) == .success,
                let windows = windowsRef as? [AXUIElement]
            else { continue }

            for element in windows {
                guard let candidate = include(element, on: spaceID) else { continue }
                results.append(candidate)
            }
        }
        return results
    }

    private func include(_ element: AXUIElement, on spaceID: CGSSpaceID) -> Candidate? {
        let role = axString(element, kAXRoleAttribute as String)
        guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }

        let subrole = axString(element, kAXSubroleAttribute as String)
        guard subrole.isEmpty || subrole == Self.standardWindowSubrole else { return nil }

        if axBool(element, kAXMinimizedAttribute as String) { return nil }
        if axBool(element, Self.fullScreenAttribute) { return nil }

        guard let size = axSize(element), size.width > 0, size.height > 0 else { return nil }

        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        guard CGSPrivate.spaceIDs(forWindow: windowID).contains(spaceID) else { return nil }

        guard let position = axPosition(element) else { return nil }
        return Candidate(element: element, position: position)
    }

    private func setFrame(_ element: AXUIElement, to rect: CGRect, primaryMaxY: CGFloat) -> Bool {
        let axOrigin = CGPoint(x: rect.minX, y: primaryMaxY - rect.maxY)
        let size = rect.size

        var sizeValue = size
        guard let sizeAX = AXValueCreate(.cgSize, &sizeValue) else { return false }
        let sizeStatus = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeAX)
        guard sizeStatus == .success else {
            log.error("AX size set failed: \(sizeStatus.rawValue)")
            return false
        }

        var originValue = axOrigin
        guard let originAX = AXValueCreate(.cgPoint, &originValue) else { return false }
        let positionStatus = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            originAX
        )
        guard positionStatus == .success else {
            log.error("AX position set failed: \(positionStatus.rawValue)")
            return false
        }
        return true
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return ""
        }
        return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? Bool) ?? false
    }

    private func axSize(_ element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func axPosition(_ element: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(ref as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
}
