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
    /// Long enough for Electron / multi-window apps under a burst of AX traffic.
    private static let axTimeoutSeconds: Float = 1.0
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

        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
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

            guard let windows = copyWindows(from: appElement) else { continue }

            for element in windows {
                AXUIElementSetMessagingTimeout(element, Self.axTimeoutSeconds)
                guard let candidate = include(element, on: spaceID) else { continue }
                results.append(candidate)
            }
        }
        return results
    }

    private func copyWindows(from appElement: AXUIElement) -> [AXUIElement]? {
        for _ in 0..<2 {
            var windowsRef: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )
            if status == .success, let windows = windowsRef as? [AXUIElement] {
                return windows
            }
        }
        return nil
    }

    private func include(_ element: AXUIElement, on spaceID: CGSSpaceID) -> Candidate? {
        let role = AXRead.string(element, kAXRoleAttribute as String)
        guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }

        let subrole = AXRead.string(element, kAXSubroleAttribute as String)
        guard subrole.isEmpty || subrole == Self.standardWindowSubrole else { return nil }

        if AXRead.bool(element, kAXMinimizedAttribute as String) { return nil }
        if AXRead.bool(element, Self.fullScreenAttribute) { return nil }

        guard let size = AXRead.size(element), size.width > 0, size.height > 0 else { return nil }

        let windowID = AXRead.windowID(element)
        guard windowID != 0 else { return nil }
        guard CGSPrivate.spaceIDs(forWindow: windowID).contains(spaceID) else { return nil }

        guard let position = AXRead.position(element) else { return nil }
        return Candidate(element: element, position: position)
    }

    private func setFrame(_ element: AXUIElement, to rect: CGRect, primaryMaxY: CGFloat) -> Bool {
        AXUIElementSetMessagingTimeout(element, Self.axTimeoutSeconds)
        let axOrigin = WindowArrangement.accessibilityOrigin(cocoaRect: rect, primaryScreenMaxY: primaryMaxY)
        let size = rect.size

        // Position first so growing a window near an edge is not rejected as off-screen.
        // A second pass runs only when the frame read back still differs.
        let first = applyFrame(element, origin: axOrigin, size: size, positionFirst: true)
        if first {
            if let readBack = readCocoaFrame(element, primaryMaxY: primaryMaxY),
               WindowArrangement.needsAnotherPass(written: rect, readBack: readBack)
            {
                if applyFrame(element, origin: axOrigin, size: size, positionFirst: true) {
                    return true
                }
            } else {
                return true
            }
        }

        // Last resort: size then position (matches some older AX clients).
        let fallback = applyFrame(element, origin: axOrigin, size: size, positionFirst: false)
        if !fallback {
            log.error("AX frame set failed for window at (\(rect.midX), \(rect.midY))")
        }
        return fallback
    }

    private func readCocoaFrame(_ element: AXUIElement, primaryMaxY: CGFloat) -> CGRect? {
        guard let origin = AXRead.position(element), let size = AXRead.size(element) else { return nil }
        let cocoaY = primaryMaxY - (origin.y + size.height)
        return CGRect(x: origin.x, y: cocoaY, width: size.width, height: size.height)
    }

    private func applyFrame(
        _ element: AXUIElement,
        origin: CGPoint,
        size: CGSize,
        positionFirst: Bool
    ) -> Bool {
        if positionFirst {
            return setPosition(element, origin) && setSize(element, size)
        }
        return setSize(element, size) && setPosition(element, origin)
    }

    private func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        var value = origin
        guard let ax = AXValueCreate(.cgPoint, &value) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
        if status != .success {
            log.error("AX position set failed: \(status.rawValue)")
            return false
        }
        return true
    }

    private func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
        if status != .success {
            log.error("AX size set failed: \(status.rawValue)")
            return false
        }
        return true
    }
}
