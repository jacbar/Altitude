import Foundation

/// Tracks a live Dock horizontal swipe and decides whether to hop when the finger lifts.
struct SwipeGestureTracker: Sendable {
    private(set) var isSwallowing = false
    private var postedForSwipe = false
    private var swipeDeadline = Date.distantPast
    private var swipePeak: Double = 0
    private var swipeDirection: DockSwipeSwitcher.Direction?

    mutating func clearIfExpired(now: Date) {
        if isSwallowing, now > swipeDeadline {
            resetTracking()
        }
    }

    /// Swallow the live gesture and only hop when the finger lifts past the commit threshold.
    /// That lets a reversed or aborted swipe cancel, matching Mission Control's habit.
    mutating func consume(
        _ swipe: DockSwipeSwitcher.HorizontalSwipe,
        now: Date,
        commitThreshold: Double
    ) -> SpaceHopDirection? {
        if swipe.began {
            postedForSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }
        isSwallowing = !swipe.ended
        swipeDeadline = now.addingTimeInterval(1.5)

        let magnitude = abs(swipe.progress)
        if magnitude >= abs(swipePeak), let direction = swipe.direction {
            swipePeak = swipe.progress
            swipeDirection = direction
        }

        guard swipe.ended else { return nil }

        var hop: SpaceHopDirection?
        if !postedForSwipe,
           abs(swipePeak) >= commitThreshold,
           let direction = swipeDirection
        {
            postedForSwipe = true
            hop = Self.hopDirection(direction)
        }
        resetTracking()
        return hop
    }

    private mutating func resetTracking() {
        postedForSwipe = false
        isSwallowing = false
        swipePeak = 0
        swipeDirection = nil
    }

    private static func hopDirection(_ direction: DockSwipeSwitcher.Direction) -> SpaceHopDirection {
        switch direction {
        case .left:
            return .previous
        case .right:
            return .next
        }
    }
}
