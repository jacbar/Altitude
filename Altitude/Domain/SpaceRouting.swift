import Foundation

/// Pure dock-swipe hop choice on one display's Space list.
enum SpaceRoute: Equatable, Sendable {
    case alreadyThere
    case otherDisplay
    case posted(steps: Int, from: Int, to: Int, destinationID: CGSSpaceID)
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
