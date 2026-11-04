import Foundation

/// Pure dock-swipe hop choice on one display's Space list.
enum SpaceRoute: Equatable, Sendable {
    case alreadyThere
    case otherDisplay
    case posted(steps: Int, from: Int, to: Int, destinationID: CGSSpaceID)
}

/// One managed display's Space strip and effective current Space for routing.
struct DisplaySpaceRouteInput: Equatable, Sendable {
    let identifier: String
    let spaceIDs: [CGSSpaceID]
    let currentID: CGSSpaceID
}

/// Prefer the nearest candidate Space on the active display.
func preferredSpaceRoute(
    candidateIDs: [CGSSpaceID],
    displaySpaceIDs: [CGSSpaceID],
    currentID: CGSSpaceID
) -> SpaceRoute {
    if candidateIDs.isEmpty || candidateIDs.contains(currentID) {
        return .alreadyThere
    }
    guard let from = displaySpaceIDs.firstIndex(of: currentID) else {
        return .otherDisplay
    }

    let ranked = candidateIDs.compactMap { id -> (CGSSpaceID, Int)? in
        guard let index = displaySpaceIDs.firstIndex(of: id) else { return nil }
        return (id, index)
    }
    guard let target = ranked.min(by: { abs($0.1 - from) < abs($1.1 - from) }) else {
        return .otherDisplay
    }
    if target.1 == from {
        return .alreadyThere
    }
    return .posted(
        steps: abs(target.1 - from),
        from: from,
        to: target.1,
        destinationID: target.0
    )
}

/// Prefer a candidate on the active display; otherwise hop (or stay) on another managed display that owns one.
///
/// - Returns `.alreadyThere` with no display when there are no candidates.
/// - Returns `.otherDisplay` only when no candidate maps to any managed display.
func preferredSpaceRoute(
    candidateIDs: [CGSSpaceID],
    displays: [DisplaySpaceRouteInput],
    activeDisplayIdentifier: String?
) -> (displayIdentifier: String?, route: SpaceRoute) {
    if candidateIDs.isEmpty {
        return (activeDisplayIdentifier, .alreadyThere)
    }

    // Same-display nearest when the active display owns any candidate.
    if let activeDisplayIdentifier,
       let active = displays.first(where: { $0.identifier == activeDisplayIdentifier }),
       candidateIDs.contains(where: { active.spaceIDs.contains($0) })
    {
        let route = preferredSpaceRoute(
            candidateIDs: candidateIDs,
            displaySpaceIDs: active.spaceIDs,
            currentID: active.currentID
        )
        return (active.identifier, route)
    }

    // Window already visible on some managed display's current Space.
    if let hit = displays.first(where: { candidateIDs.contains($0.currentID) }) {
        return (hit.identifier, .alreadyThere)
    }

    // Nearest in-display hop among displays that own candidates; fewest steps wins.
    var best: (displayIdentifier: String, route: SpaceRoute, steps: Int)?
    for display in displays {
        let route = preferredSpaceRoute(
            candidateIDs: candidateIDs,
            displaySpaceIDs: display.spaceIDs,
            currentID: display.currentID
        )
        switch route {
        case .alreadyThere:
            return (display.identifier, .alreadyThere)
        case .posted(let steps, _, _, _):
            if best == nil || steps < best!.steps {
                best = (display.identifier, route, steps)
            }
        case .otherDisplay:
            continue
        }
    }

    if let best {
        return (best.displayIdentifier, best.route)
    }
    return (nil, .otherDisplay)
}

/// Digit hotkey hop to one Space on a single display strip (active or not).
///
/// - Returns `.alreadyThere` when `targetSpaceID` is already current.
/// - Returns `.posted` when both IDs sit on the strip and differ.
/// - Returns `.otherDisplay` when either ID is missing from the strip.
func digitSwitchRoute(
    targetSpaceID: CGSSpaceID,
    displaySpaceIDs: [CGSSpaceID],
    currentID: CGSSpaceID
) -> SpaceRoute {
    guard let from = displaySpaceIDs.firstIndex(of: currentID),
          let to = displaySpaceIDs.firstIndex(of: targetSpaceID)
    else {
        return .otherDisplay
    }
    if from == to {
        return .alreadyThere
    }
    return .posted(
        steps: abs(to - from),
        from: from,
        to: to,
        destinationID: targetSpaceID
    )
}

/// Move one Space left or right on the active display.
func oneSpaceRoute(
    direction: SpaceHopDirection,
    displaySpaceIDs: [CGSSpaceID],
    currentIndex: Int
) -> SpaceRoute {
    switch direction {
    case .previous:
        guard currentIndex > 0 else { return .alreadyThere }
        let to = currentIndex - 1
        return .posted(
            steps: 1,
            from: currentIndex,
            to: to,
            destinationID: displaySpaceIDs[to]
        )
    case .next:
        guard currentIndex < displaySpaceIDs.count - 1 else { return .alreadyThere }
        let to = currentIndex + 1
        return .posted(
            steps: 1,
            from: currentIndex,
            to: to,
            destinationID: displaySpaceIDs[to]
        )
    }
}
