import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "SkyLightBackend")

/// SkyLight-backed implementation of `SpaceService`.
/// v1: flattens user desktops across displays into a single 1-based index list.
final class SkyLightBackend: SpaceService {
    var instantSwitching = false

    private let focusResolver: FocusedWindowResolver
    private var prediction: SpacePrediction?

    init(focusResolver: FocusedWindowResolver = FocusedWindowResolver()) {
        self.focusResolver = focusResolver
    }

    func snapshot() -> SpaceSnapshot {
        let layout = readLayout()
        // Indicator follows live CGS only. Dock-swipe prediction is for routing hops,
        // not for painting the menu bar (prediction can desync from the true Space).
        let activeID = liveActiveSpaceID(in: layout)
        let current = layout.desktops.first { $0.id == activeID }?.index
        let spaces = layout.desktops.map { space in
            DesktopSpace(
                index: space.index,
                id: space.id,
                displayIdentifier: space.displayIdentifier,
                uuid: space.uuid,
                isCurrent: space.index == current
            )
        }
        return SpaceSnapshot(spaces: spaces, currentIndex: current)
    }

    func switchTo(index: Int) throws {
        // Dock-swipe events are ignored unless Accessibility is granted.
        guard focusResolver.isAccessibilityTrusted else {
            throw SpaceServiceError.accessibilityDenied
        }

        let layout = readLayout()
        let liveID = CGSPrivate.activeSpaceID()
        expirePredictionIfNeeded(activeID: liveID)
        let prediction = self.prediction

        guard let target = layout.desktops.first(where: { $0.index == index }) else {
            throw SpaceServiceError.invalidSpaceIndex(index)
        }
        guard let display = layout.displays.first(where: { $0.identifier == target.displayIdentifier }) else {
            throw SpaceServiceError.spacesUnavailable
        }

        // Dock-swipe follows the display under the pointer; warp there first when needed.
        if let activeDisplay = activeDisplayIdentifier(in: layout, prediction: prediction),
           activeDisplay != display.identifier
        {
            focusDisplayBestEffort(display.identifier)
        }

        guard let currentID = currentSpaceID(on: display, prediction: prediction) else {
            throw SpaceServiceError.spacesUnavailable
        }
        let route = digitSwitchRoute(
            targetSpaceID: target.id,
            displaySpaceIDs: display.spaceIDs,
            currentID: currentID
        )
        switch route {
        case .alreadyThere:
            return
        case .otherDisplay:
            throw SpaceServiceError.spacesUnavailable
        case .posted(_, let from, let to, let destinationID):
            performSwipe(
                on: display,
                from: from,
                to: to,
                destinationID: destinationID,
                instant: instantSwitching
            )
        }
    }

    func switchToPreferredSpace(among spaceIDs: [CGSSpaceID], instant: Bool) -> InstantSwitchResult {
        guard focusResolver.isAccessibilityTrusted else { return .unavailable }
        let layout = readLayout()
        let liveID = CGSPrivate.activeSpaceID()
        expirePredictionIfNeeded(activeID: liveID)
        let prediction = self.prediction

        let displays = layout.displays.compactMap { display -> DisplaySpaceRouteInput? in
            guard let currentID = currentSpaceID(on: display, prediction: prediction) else { return nil }
            return DisplaySpaceRouteInput(
                identifier: display.identifier,
                spaceIDs: display.spaceIDs,
                currentID: currentID
            )
        }
        guard !displays.isEmpty else { return .unavailable }

        let (resolvedDisplayID, route) = preferredSpaceRoute(
            candidateIDs: spaceIDs,
            displays: displays,
            activeDisplayIdentifier: activeDisplayIdentifier(in: layout, prediction: prediction)
        )
        switch route {
        case .alreadyThere:
            return .alreadyThere
        case .otherDisplay:
            return .otherDisplay
        case .posted:
            guard let resolvedDisplayID,
                  let display = layout.displays.first(where: { $0.identifier == resolvedDisplayID })
            else {
                return .unavailable
            }
            return apply(route, on: display, instant: instant)
        }
    }

    func switchInstantly(toPreferredSpaceAmong spaceIDs: [CGSSpaceID]) -> InstantSwitchResult {
        switchToPreferredSpace(among: spaceIDs, instant: true)
    }

    func moveOneSpaceInstantly(direction: SpaceHopDirection) -> InstantSwitchResult {
        guard focusResolver.isAccessibilityTrusted else { return .unavailable }
        let layout = readLayout()
        let liveID = CGSPrivate.activeSpaceID()
        expirePredictionIfNeeded(activeID: liveID)
        let prediction = self.prediction

        guard let activeDisplayID = activeDisplayIdentifier(in: layout, prediction: prediction),
              let display = layout.displays.first(where: { $0.identifier == activeDisplayID }),
              let currentID = currentSpaceID(on: display, prediction: prediction),
              let from = display.spaceIDs.firstIndex(of: currentID),
              !display.spaceIDs.isEmpty
        else {
            return .unavailable
        }

        let route = oneSpaceRoute(
            direction: direction,
            displaySpaceIDs: display.spaceIDs,
            currentIndex: from
        )
        return apply(route, on: display, instant: true)
    }

    func moveFocusedWindow(to index: Int) throws {
        guard focusResolver.isAccessibilityTrusted else {
            throw SpaceServiceError.accessibilityDenied
        }
        let desktops = readLayout().desktops
        guard let target = desktops.first(where: { $0.index == index }) else {
            throw SpaceServiceError.invalidSpaceIndex(index)
        }
        guard let windowID = focusResolver.focusedWindowID() else {
            throw SpaceServiceError.noFocusedWindow
        }

        log.info("Moving window \(windowID) to desktop \(index) (space \(target.id))")
        CGSPrivate.moveWindowsToManagedSpace(windowIDs: [windowID], spaceID: target.id)
    }

    private func apply(
        _ route: SpaceRoute,
        on display: ManagedDisplay,
        instant: Bool
    ) -> InstantSwitchResult {
        switch route {
        case .alreadyThere:
            return .alreadyThere
        case .otherDisplay:
            return .otherDisplay
        case .posted(let steps, let from, let to, let destinationID):
            performSwipe(
                on: display,
                from: from,
                to: to,
                destinationID: destinationID,
                instant: instant
            )
            return .posted(steps: steps)
        }
    }

    private func performSwipe(
        on display: ManagedDisplay,
        from: Int,
        to: Int,
        destinationID: CGSSpaceID,
        instant: Bool
    ) {
        let steps = abs(to - from)
        let direction: DockSwipeSwitcher.Direction = to > from ? .right : .left
        log.info(
            "Switching via dock-swipe (\(steps) step(s) \(direction == .right ? "right" : "left", privacy: .public), instant=\(instant, privacy: .public))"
        )
        DockSwipeSwitcher.swipe(direction, steps: steps, instant: instant)
        let duration = DockSwipeSwitcher.estimatedDuration(steps: steps, instant: instant)
        prediction = SpacePrediction(
            spaceID: destinationID,
            displayIdentifier: display.identifier,
            expiry: Date().addingTimeInterval(duration + Timing.predictionSlack)
        )
    }

    func acknowledgeSystemSpaceChange() {
        // Intermediate hops of a multi-step switch also land here, so the prediction
        // survives until the system reaches it or it expires.
        expirePredictionIfNeeded(activeID: CGSPrivate.activeSpaceID())
    }

    // MARK: - Private

    private func livePrediction(activeID: CGSSpaceID, now: Date = Date()) -> SpacePrediction? {
        prediction?.live(activeID: activeID, now: now)
    }

    private func expirePredictionIfNeeded(activeID: CGSSpaceID, now: Date = Date()) {
        if prediction.shouldExpire(activeID: activeID, now: now) {
            prediction = nil
        }
    }

    private func liveActiveSpaceID(in layout: ManagedLayout) -> CGSSpaceID? {
        let liveID = CGSPrivate.activeSpaceID()
        if layout.displays.contains(where: { $0.spaceIDs.contains(liveID) }) {
            return liveID
        }
        return layout.displays.first?.currentSpaceID
    }

    /// Prefers in-flight dock-swipe prediction so multi-step hops keep routing correctly.
    private func activeSpaceID(in layout: ManagedLayout, prediction: SpacePrediction?) -> CGSSpaceID? {
        if let prediction {
            return prediction.spaceID
        }
        return liveActiveSpaceID(in: layout)
    }

    private func activeDisplayIdentifier(
        in layout: ManagedLayout,
        prediction: SpacePrediction?
    ) -> String? {
        guard let activeID = activeSpaceID(in: layout, prediction: prediction) else { return nil }
        return layout.displays.first { $0.spaceIDs.contains(activeID) }?.identifier
    }

    func currentSpaceID(on screen: NSScreen) -> CGSSpaceID? {
        let layout = readLayout()
        guard !layout.displays.isEmpty else { return nil }
        let prediction = livePrediction(activeID: CGSPrivate.activeSpaceID())

        guard let uuidString = displayUUIDString(for: screen) else {
            return fallbackCurrentSpaceID(in: layout, prediction: prediction)
        }

        if let display = layout.displays.first(where: {
            $0.identifier.caseInsensitiveCompare(uuidString) == .orderedSame
        }) {
            return currentSpaceID(on: display, prediction: prediction)
        }

        return fallbackCurrentSpaceID(in: layout, prediction: prediction)
    }

    /// Best-effort: move the pointer to the center of the managed display so dock-swipe hits it.
    private func focusDisplayBestEffort(_ displayIdentifier: String) {
        guard let screen = nsScreen(matchingDisplayIdentifier: displayIdentifier) else {
            log.error("Could not match managed display to NSScreen for focus warp")
            return
        }
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY else {
            return
        }
        let frame = screen.visibleFrame
        // Cocoa bottom-left → Quartz top-left (same primary maxY flip as AX).
        let point = CGPoint(x: frame.midX, y: primaryMaxY - frame.midY)
        let error = CGWarpMouseCursorPosition(point)
        if error != .success {
            log.error("CGWarpMouseCursorPosition failed: \(error.rawValue)")
        }
    }

    private func nsScreen(matchingDisplayIdentifier identifier: String) -> NSScreen? {
        for screen in NSScreen.screens {
            guard let uuidString = displayUUIDString(for: screen) else { continue }
            if identifier.caseInsensitiveCompare(uuidString) == .orderedSame {
                return screen
            }
        }
        return nil
    }

    private func displayUUIDString(for screen: NSScreen) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            log.error("NSScreen missing NSScreenNumber")
            return nil
        }
        let displayID = CGDirectDisplayID(truncatingIfNeeded: number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let uuidString = CFUUIDCreateString(nil, uuid) as String?
        else {
            log.error("Could not resolve display UUID for screen")
            return nil
        }
        return uuidString
    }

    private func fallbackCurrentSpaceID(
        in layout: ManagedLayout,
        prediction: SpacePrediction?
    ) -> CGSSpaceID? {
        if layout.displays.count == 1 {
            return currentSpaceID(on: layout.displays[0], prediction: prediction)
        }
        log.error("Could not match NSScreen to a managed display among \(layout.displays.count)")
        return nil
    }

    private func currentSpaceID(
        on display: ManagedDisplay,
        prediction: SpacePrediction?
    ) -> CGSSpaceID? {
        if let prediction, prediction.displayIdentifier == display.identifier {
            return prediction.spaceID
        }
        return display.currentSpaceID
    }

    private func readLayout() -> ManagedLayout {
        let rawDisplays = CGSPrivate.copyManagedDisplaySpaces()
            ?? (SkyLightBridgedSPI.copyManagedDisplaySpaces() as? [[String: Any]])

        guard let rawDisplays else {
            log.error("CGSCopyManagedDisplaySpaces returned nil")
            return ManagedLayout(displays: [], desktops: [])
        }

        return ManagedDisplayLayout.parse(rawDisplays)
    }
}
