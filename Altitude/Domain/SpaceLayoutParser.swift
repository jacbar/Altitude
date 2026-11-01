import Foundation

struct ParsedDisplay: Equatable, Sendable {
    let identifier: String
    /// Every Space on the display in Mission Control order, fullscreen apps included,
    /// because each one costs a dock-swipe step.
    let spaceIDs: [CGSSpaceID]
    let currentSpaceID: CGSSpaceID?
}

struct ParsedLayout: Equatable, Sendable {
    let displays: [ParsedDisplay]
    let desktops: [DesktopSpace]
}

/// Pure walk over the SkyLight managed-display-spaces dictionary tree.
enum SpaceLayoutParser {
    static func parse(_ rawDisplays: [[String: Any]]) -> ParsedLayout {
        var displays: [ParsedDisplay] = []
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
                ParsedDisplay(
                    identifier: displayIdentifier,
                    spaceIDs: spaceIDs,
                    currentSpaceID: currentSpaceID
                )
            )
        }

        return ParsedLayout(displays: displays, desktops: desktops)
    }

    private static func spaceID(from value: Any?) -> CGSSpaceID? {
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
