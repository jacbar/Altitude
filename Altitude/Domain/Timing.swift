import Foundation

enum Timing {
    /// MenuBarController waits before reapplying hotkeys.
    static let hotkeyRefresh: TimeInterval = 0.45

    /// SystemMotionSuppressor.activate focus retries.
    static let focusRetryShort: TimeInterval = 0.05
    /// SystemMotionSuppressor.activate focus retries.
    static let focusRetryMid: TimeInterval = 0.12
    /// SystemMotionSuppressor.activate focus retries.
    static let focusRetryLong: TimeInterval = 0.28

    /// Backup clear of isActivatingInternally.
    static let activationGuard: TimeInterval = 1.0

    /// Cancel an open Command-Tab session after this much idle time.
    static let commandTabIdle: TimeInterval = 10

    static let instantLandingBase: TimeInterval = 0.08
    static let instantLandingPerStep: TimeInterval = 0.06

    static func instantLandingDelay(steps: Int) -> TimeInterval {
        0.08 + 0.06 * Double(max(steps, 1))
    }

    /// SwipeGesture defaults and the suppressor call.
    static let swipeCommitThreshold: Double = 0.08
    /// SwipeGesture defaults and the suppressor call.
    static let swipeStuckInterval: TimeInterval = 1.5

    /// SkyLightBackend prediction expiry = duration + slack.
    static let predictionSlack: TimeInterval = 1.0

    /// DockSwipeSwitcher smoothStepGap.
    static let dockSwipeStepGap: TimeInterval = 0.28
}
