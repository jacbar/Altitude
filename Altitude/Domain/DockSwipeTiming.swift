import Foundation

/// Pure duration math for dock-swipe gesture posting (shared by Backend and tests).
enum DockSwipeTiming {
    static let smoothFrameCount = 24
    static let smoothFrameInterval: TimeInterval = 0.008
    static let smoothStepGap: TimeInterval = Timing.dockSwipeStepGap

    /// Time spent posting gesture frames; the Dock's own animation comes on top.
    static func estimatedDuration(steps: Int, instant: Bool) -> TimeInterval {
        guard !instant, steps > 0 else { return 0 }
        let perStep = Double(smoothFrameCount) * smoothFrameInterval
        return Double(steps) * perStep + Double(steps - 1) * smoothStepGap
    }
}
