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

        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY else {
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
        let role = element.axString(kAXRoleAttribute as String)
        guard WindowArrangement.acceptsArrangeRole(role) else {
            log.debug("Skip window: role=\(role, privacy: .public)")
            return nil
        }

        let subrole = element.axString(kAXSubroleAttribute as String)
        guard WindowArrangement.acceptsArrangeSubrole(subrole) else {
            log.debug("Skip window: subrole=\(subrole, privacy: .public)")
            return nil
        }

        if element.axBool(kAXMinimizedAttribute as String) {
            log.debug("Skip window: minimized")
            return nil
        }
        if element.axBool(Self.fullScreenAttribute) {
            log.debug("Skip window: fullscreen")
            return nil
        }

        guard let size = element.axSize(), size.width > 0, size.height > 0 else {
            log.debug("Skip window: zero-size")
            return nil
        }

        let windowID = element.axWindowID()
        guard windowID != 0 else {
            log.debug("Skip window: no CGWindowID")
            return nil
        }

        let windowSpaces = CGSPrivate.spaceIDs(forWindow: windowID)
        let activeSpace = CGSPrivate.activeSpaceID()
        switch WindowArrangement.spaceMembership(
            windowSpaceIDs: windowSpaces,
            arrangeSpaceID: spaceID,
            activeSpaceID: activeSpace
        ) {
        case .onArrangeSpace:
            break
        case .emptyOnActiveArrangeSpace:
            log.info(
                "Include window \(windowID) with empty space membership on active arrange Space \(spaceID)"
            )
        case .excluded:
            log.debug(
                "Skip window \(windowID): spaces=\(windowSpaces.map(String.init).joined(separator: ","), privacy: .public) arrange=\(spaceID)"
            )
            return nil
        }

        guard let position = element.axPosition() else {
            log.debug("Skip window \(windowID): no position")
            return nil
        }
        return Candidate(element: element, position: position)
    }

    private func setFrame(_ element: AXUIElement, to rect: CGRect, primaryMaxY: CGFloat) -> Bool {
        AXUIElementSetMessagingTimeout(element, Self.axTimeoutSeconds)
        let axOrigin = WindowArrangement.accessibilityOrigin(cocoaRect: rect, primaryMaxY: primaryMaxY)
        let size = rect.size

        // Position first so growing a window near an edge is not rejected as off-screen.
        // A second pass is needed for apps that clamp or ignore the first write.
        let first = applyFrame(element, origin: axOrigin, size: size, positionFirst: true)
        let second = applyFrame(element, origin: axOrigin, size: size, positionFirst: true)
        if first || second { return true }

        // Last resort: size then position (matches some older AX clients).
        let fallback = applyFrame(element, origin: axOrigin, size: size, positionFirst: false)
        if !fallback {
            log.error("AX frame set failed for window at (\(rect.midX), \(rect.midY))")
        }
        return fallback
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
