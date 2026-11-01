import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "SkyLightBackend")

/// SkyLight-backed implementation of `SpaceService`.
/// v1: flattens user desktops across displays into a single 1-based index list.
final class SkyLightBackend: SpaceService {
    private typealias Display = ParsedDisplay
    private typealias Layout = ParsedLayout

    /// Where a dock-swipe is headed; CGS lags behind until the Dock finishes.
    private struct Prediction {
        let spaceID: CGSSpaceID
        let displayIdentifier: String
        let expiry: Date
    }

    /// Slack covering Dock animation after the posted gesture.
    private static let predictionSlack: TimeInterval = 1.0
    private static let layoutCacheTTL: TimeInterval = 0.05

    var instantSwitching = false

    private let focusResolver: FocusedWindowResolver
    private var prediction: Prediction?
    private var cachedLayout: Layout?
    private var cachedLayoutAt: Date?

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

        expirePrediction(activeID: CGSPrivate.activeSpaceID())
        let layout = readLayout()
        guard let target = layout.desktops.first(where: { $0.index == index }) else {
            throw SpaceServiceError.invalidSpaceIndex(index)
        }
        guard let display = layout.displays.first(where: { $0.identifier == target.displayIdentifier }) else {
            throw SpaceServiceError.spacesUnavailable
        }
        // A dock-swipe only moves the active display.
        if let activeDisplay = activeDisplayIdentifier(in: layout), activeDisplay != display.identifier {
            throw SpaceServiceError.crossDisplaySwitch(index)
        }
        guard let currentID = currentSpaceID(on: display),
              let from = display.spaceIDs.firstIndex(of: currentID),
              let to = display.spaceIDs.firstIndex(of: target.id)
        else {
            throw SpaceServiceError.spacesUnavailable
        }
        if from == to {
            return
        }

        performSwipe(
            on: display,
            from: from,
            to: to,
            destinationID: target.id,
            instant: instantSwitching
        )
    }

    func switchToPreferredSpace(among spaceIDs: [CGSSpaceID], instant: Bool) -> InstantSwitchResult {
        guard focusResolver.isAccessibilityTrusted else { return .unavailable }
        expirePrediction(activeID: CGSPrivate.activeSpaceID())
        let layout = readLayout()
        guard let activeDisplayID = activeDisplayIdentifier(in: layout),
              let display = layout.displays.first(where: { $0.identifier == activeDisplayID }),
              let currentID = currentSpaceID(on: display),
              let from = display.spaceIDs.firstIndex(of: currentID)
        else {
            return .unavailable
        }
        if spaceIDs.isEmpty || spaceIDs.contains(currentID) {
            return .alreadyThere
        }

        let ranked = spaceIDs.compactMap { id -> (CGSSpaceID, Int)? in
            guard let index = display.spaceIDs.firstIndex(of: id) else { return nil }
            return (id, index)
        }
        guard let target = ranked.min(by: { abs($0.1 - from) < abs($1.1 - from) }) else {
            return .otherDisplay
        }
        if target.1 == from {
            return .alreadyThere
        }
        performSwipe(on: display, from: from, to: target.1, destinationID: target.0, instant: instant)
        return .posted(steps: abs(target.1 - from))
    }

    func switchInstantly(toPreferredSpaceAmong spaceIDs: [CGSSpaceID]) -> InstantSwitchResult {
        switchToPreferredSpace(among: spaceIDs, instant: true)
    }

    func moveOneSpaceInstantly(direction: SpaceHopDirection) -> InstantSwitchResult {
        guard focusResolver.isAccessibilityTrusted else { return .unavailable }
        expirePrediction(activeID: CGSPrivate.activeSpaceID())
        let layout = readLayout()
        guard let activeDisplayID = activeDisplayIdentifier(in: layout),
              let display = layout.displays.first(where: { $0.identifier == activeDisplayID }),
              let currentID = currentSpaceID(on: display),
              let from = display.spaceIDs.firstIndex(of: currentID),
              !display.spaceIDs.isEmpty
        else {
            return .unavailable
        }

        let to: Int
        switch direction {
        case .previous:
            guard from > 0 else { return .alreadyThere }
            to = from - 1
        case .next:
            guard from < display.spaceIDs.count - 1 else { return .alreadyThere }
            to = from + 1
        }
        performSwipe(
            on: display,
            from: from,
            to: to,
            destinationID: display.spaceIDs[to],
            instant: true
        )
        return .posted(steps: 1)
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

    private func performSwipe(
        on display: Display,
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
        prediction = Prediction(
            spaceID: destinationID,
            displayIdentifier: display.identifier,
            expiry: Date().addingTimeInterval(duration + Self.predictionSlack)
        )
    }

    func acknowledgeSystemSpaceChange() {
        // Intermediate hops of a multi-step switch also land here, so the prediction
        // survives until the system reaches it or it expires.
        cachedLayout = nil
        cachedLayoutAt = nil
        expirePrediction(activeID: CGSPrivate.activeSpaceID())
    }

    // MARK: - Private

    /// Pure lookup; does not clear `prediction`.
    private func predictionIfValid(activeID: CGSSpaceID, now: Date) -> Prediction? {
        guard let prediction, now < prediction.expiry, prediction.spaceID != activeID else {
            return nil
        }
        return prediction
    }

    private func expirePrediction(activeID: CGSSpaceID, now: Date = Date()) {
        guard let prediction else { return }
        if now >= prediction.expiry || prediction.spaceID == activeID {
            self.prediction = nil
        }
    }

    private func liveActiveSpaceID(in layout: Layout) -> CGSSpaceID? {
        let liveID = CGSPrivate.activeSpaceID()
        if layout.displays.contains(where: { $0.spaceIDs.contains(liveID) }) {
            return liveID
        }
        return layout.displays.first?.currentSpaceID
    }

    /// Prefers in-flight dock-swipe prediction so multi-step hops keep routing correctly.
    private func activeSpaceID(in layout: Layout) -> CGSSpaceID? {
        let liveID = CGSPrivate.activeSpaceID()
        if let prediction = predictionIfValid(activeID: liveID, now: Date()) {
            return prediction.spaceID
        }
        return liveActiveSpaceID(in: layout)
    }

    private func activeDisplayIdentifier(in layout: Layout) -> String? {
        guard let activeID = activeSpaceID(in: layout) else { return nil }
        return layout.displays.first { $0.spaceIDs.contains(activeID) }?.identifier
    }

    func currentSpaceID(on screen: NSScreen) -> CGSSpaceID? {
        expirePrediction(activeID: CGSPrivate.activeSpaceID())
        let layout = readLayout()
        guard !layout.displays.isEmpty else { return nil }

        let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            log.error("NSScreen missing NSScreenNumber")
            return fallbackCurrentSpaceID(in: layout)
        }
        let displayID = CGDirectDisplayID(truncatingIfNeeded: number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let uuidString = CFUUIDCreateString(nil, uuid) as String?
        else {
            log.error("Could not resolve display UUID for screen")
            return fallbackCurrentSpaceID(in: layout)
        }

        if let display = layout.displays.first(where: {
            $0.identifier.caseInsensitiveCompare(uuidString) == .orderedSame
        }) {
            return currentSpaceID(on: display)
        }

        return fallbackCurrentSpaceID(in: layout)
    }

    private func fallbackCurrentSpaceID(in layout: Layout) -> CGSSpaceID? {
        if layout.displays.count == 1 {
            return currentSpaceID(on: layout.displays[0])
        }
        log.error("Could not match NSScreen to a managed display among \(layout.displays.count)")
        return nil
    }

    private func currentSpaceID(on display: Display) -> CGSSpaceID? {
        if let prediction = predictionIfValid(activeID: CGSPrivate.activeSpaceID(), now: Date()),
           prediction.displayIdentifier == display.identifier
        {
            return prediction.spaceID
        }
        return display.currentSpaceID
    }

    private func readLayout() -> Layout {
        let now = Date()
        if let cachedLayout, let cachedLayoutAt, now.timeIntervalSince(cachedLayoutAt) < Self.layoutCacheTTL {
            return cachedLayout
        }

        let rawDisplays = CGSPrivate.copyManagedDisplaySpaces()
            ?? (SkyLightBridgedSPI.copyManagedDisplaySpaces() as? [[String: Any]])

        guard let rawDisplays else {
            log.error("CGSCopyManagedDisplaySpaces returned nil")
            let empty = Layout(displays: [], desktops: [])
            self.cachedLayout = empty
            self.cachedLayoutAt = now
            return empty
        }

        let layout = SpaceLayoutParser.parse(rawDisplays)
        self.cachedLayout = layout
        self.cachedLayoutAt = now
        return layout
    }
}
