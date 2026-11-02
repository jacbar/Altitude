import Foundation

enum SwipeDirection: Equatable, Sendable {
    case left
    case right
}

struct SwipeSample: Equatable, Sendable {
    let progress: Double
    let direction: SwipeDirection?
    let began: Bool
    let ended: Bool
}

struct SwipeGestureState: Equatable, Sendable {
    var postedForSwipe = false
    var swallowingSwipe = false
    var swipePeak: Double = 0
    var swipeDirection: SwipeDirection?
    var swipeDeadline = Date.distantPast

    /// Swallow the live gesture and only commit when the finger lifts past the threshold.
    /// That lets a reversed or aborted swipe cancel, matching Mission Control's habit.
    mutating func consume(
        _ sample: SwipeSample,
        now: Date,
        commitThreshold: Double = Timing.swipeCommitThreshold,
        stuckInterval: TimeInterval = Timing.swipeStuckInterval
    ) -> SwipeDirection? {
        if sample.began {
            postedForSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }
        swallowingSwipe = !sample.ended
        swipeDeadline = now.addingTimeInterval(stuckInterval)

        let magnitude = abs(sample.progress)
        if magnitude >= abs(swipePeak), let direction = sample.direction {
            swipePeak = sample.progress
            swipeDirection = direction
        }

        var committed: SwipeDirection?
        if sample.ended {
            if !postedForSwipe,
               abs(swipePeak) >= commitThreshold,
               let direction = swipeDirection
            {
                postedForSwipe = true
                committed = direction
            }
            postedForSwipe = false
            swallowingSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }
        return committed
    }

    /// Clears an open swallow after the deadline so companion events stop being dropped.
    mutating func expireIfStuck(now: Date) -> Bool {
        guard swallowingSwipe, now > swipeDeadline else { return false }
        swallowingSwipe = false
        postedForSwipe = false
        swipePeak = 0
        swipeDirection = nil
        return true
    }
}
