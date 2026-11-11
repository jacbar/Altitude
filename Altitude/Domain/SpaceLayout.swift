import Foundation

/// One managed display and every Space on it in Mission Control order.
struct ManagedDisplay: Equatable, Sendable {
    let identifier: String
    /// Every Space on the display, fullscreen apps included — each costs a dock-swipe step.
    let spaceIDs: [CGSSpaceID]
    let currentSpaceID: CGSSpaceID?
}

/// Flattened Mission Control layout across displays.
struct ManagedLayout: Equatable, Sendable {
    let displays: [ManagedDisplay]
    let desktops: [DesktopSpace]
}

/// Pure parse of `CGSCopyManagedDisplaySpaces` / bridged dictionaries.
enum ManagedDisplayLayout {
    static func parse(_ rawDisplays: [[String: Any]]) -> ManagedLayout {
        var displays: [ManagedDisplay] = []
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
                ManagedDisplay(
                    identifier: displayIdentifier,
                    spaceIDs: spaceIDs,
                    currentSpaceID: currentSpaceID
                )
            )
        }

        return ManagedLayout(displays: displays, desktops: desktops)
    }

    static func spaceID(from value: Any?) -> CGSSpaceID? {
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

/// Where a dock-swipe is headed; CGS lags behind until the Dock finishes.
struct SpacePrediction: Equatable, Sendable {
    let spaceID: CGSSpaceID
    let displayIdentifier: String
    let expiry: Date

    /// Returns `self` while the prediction still applies; never mutates storage.
    func live(activeID: CGSSpaceID, now: Date) -> SpacePrediction? {
        guard now < expiry, spaceID != activeID else { return nil }
        return self
    }
}

/// Dock-swipe follows keyboard/menu-bar focus, not an in-flight hop prediction.
func needsCrossDisplayFocus(
    targetDisplayIdentifier: String,
    liveActiveDisplayIdentifier: String?
) -> Bool {
    liveActiveDisplayIdentifier != targetDisplayIdentifier
}

extension Optional where Wrapped == SpacePrediction {
    /// True when there is no prediction, it has expired, the system has reached it,
    /// or focus has moved to another display (prediction is for same-strip chaining only).
    func shouldExpire(
        activeID: CGSSpaceID,
        now: Date,
        liveActiveDisplayIdentifier: String? = nil
    ) -> Bool {
        guard let prediction = self else { return true }
        if let liveActiveDisplayIdentifier,
           liveActiveDisplayIdentifier != prediction.displayIdentifier
        {
            return true
        }
        return now >= prediction.expiry || prediction.spaceID == activeID
    }
}
