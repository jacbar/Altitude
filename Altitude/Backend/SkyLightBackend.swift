import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "SkyLightBackend")

/// SkyLight-backed implementation of `SpaceService`.
/// v1: flattens user desktops across displays into a single 1-based index list.
final class SkyLightBackend: SpaceService {
    private struct Display {
        let identifier: String
        /// Every Space on the display in Mission Control order, fullscreen apps included,
        /// because each one costs a dock-swipe step.
        let spaceIDs: [CGSSpaceID]
        let currentSpaceID: CGSSpaceID?
    }

    private struct Layout {
        let displays: [Display]
        let desktops: [DesktopSpace]
    }

    /// Where a dock-swipe is headed; CGS lags behind until the Dock finishes.
    private struct Prediction {
        let spaceID: CGSSpaceID
        let displayIdentifier: String
        let expiry: Date
    }

    var instantSwitching = false

    private let focusResolver: FocusedWindowResolver
    private var prediction: Prediction?

    init(focusResolver: FocusedWindowResolver = FocusedWindowResolver()) {
        self.focusResolver = focusResolver
    }

    func snapshot() -> SpaceSnapshot {
        let layout = readLayout()
        let activeID = activeSpaceID(in: layout)
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

        let steps = abs(to - from)
        let direction: DockSwipeSwitcher.Direction = to > from ? .right : .left
        log.info(
            "Switching to desktop \(index) via dock-swipe (\(steps) step(s) \(direction == .right ? "right" : "left", privacy: .public))"
        )

        DockSwipeSwitcher.swipe(direction, steps: steps, instant: instantSwitching)
        let duration = DockSwipeSwitcher.estimatedDuration(steps: steps, instant: instantSwitching)
        prediction = Prediction(
            spaceID: target.id,
            displayIdentifier: display.identifier,
            expiry: Date().addingTimeInterval(duration + 1.0)
        )
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

    func acknowledgeSystemSpaceChange() {
        // Intermediate hops of a multi-step switch also land here, so the prediction
        // survives until the system reaches it or it expires.
        _ = livePrediction(activeID: CGSPrivate.activeSpaceID())
    }

    // MARK: - Private

    private func livePrediction(activeID: CGSSpaceID) -> Prediction? {
        guard let prediction, Date() < prediction.expiry, prediction.spaceID != activeID else {
            prediction = nil
            return nil
        }
        return prediction
    }

    private func activeSpaceID(in layout: Layout) -> CGSSpaceID? {
        let liveID = CGSPrivate.activeSpaceID()
        if let prediction = livePrediction(activeID: liveID) {
            return prediction.spaceID
        }
        if layout.displays.contains(where: { $0.spaceIDs.contains(liveID) }) {
            return liveID
        }
        return layout.displays.first?.currentSpaceID
    }

    private func activeDisplayIdentifier(in layout: Layout) -> String? {
        guard let activeID = activeSpaceID(in: layout) else { return nil }
        return layout.displays.first { $0.spaceIDs.contains(activeID) }?.identifier
    }

    private func currentSpaceID(on display: Display) -> CGSSpaceID? {
        if let prediction = livePrediction(activeID: CGSPrivate.activeSpaceID()),
           prediction.displayIdentifier == display.identifier
        {
            return prediction.spaceID
        }
        return display.currentSpaceID
    }

    private func readLayout() -> Layout {
        let rawDisplays = CGSPrivate.copyManagedDisplaySpaces()
            ?? (SkyLightBridgedSPI.copyManagedDisplaySpaces() as? [[String: Any]])

        guard let rawDisplays else {
            log.error("CGSCopyManagedDisplaySpaces returned nil")
            return Layout(displays: [], desktops: [])
        }

        var displays: [Display] = []
        var desktops: [DesktopSpace] = []
        var nextIndex = 1

        for rawDisplay in rawDisplays {
            guard let displayIdentifier = rawDisplay["Display Identifier"] as? String else { continue }
            let currentSpaceID = spaceID(from: rawDisplay["Current Space"])
            let spaces = (rawDisplay["Spaces"] as? [[String: Any]]) ?? []
            var spaceIDs: [CGSSpaceID] = []

            for rawSpace in spaces {
                guard let id = spaceID(from: rawSpace) else { continue }
                spaceIDs.append(id)

                let type = (rawSpace["type"] as? NSNumber)?.intValue
                    ?? (rawSpace["type"] as? Int)
                    ?? 0
                // type 0 = user desktop; fullscreen (4) / system spaces get no index
                guard type == 0 else { continue }

                desktops.append(
                    DesktopSpace(
                        index: nextIndex,
                        id: id,
                        displayIdentifier: displayIdentifier,
                        uuid: rawSpace["uuid"] as? String,
                        isCurrent: currentSpaceID == id
                    )
                )
                nextIndex += 1
            }

            displays.append(
                Display(identifier: displayIdentifier, spaceIDs: spaceIDs, currentSpaceID: currentSpaceID)
            )
        }

        return Layout(displays: displays, desktops: desktops)
    }

    private func spaceID(from value: Any?) -> CGSSpaceID? {
        if let dict = value as? [String: Any] {
            if let number = dict["ManagedSpaceID"] as? NSNumber {
                return number.uint64Value
            }
            if let number = dict["id64"] as? NSNumber {
                return number.uint64Value
            }
            if let number = dict["id"] as? NSNumber {
                return number.uint64Value
            }
        }
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        return nil
    }
}
