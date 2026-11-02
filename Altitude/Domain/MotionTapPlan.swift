import CoreGraphics
import Foundation

/// Which CGEvent taps SystemMotionSuppressor should install for a mode.
struct MotionTapPlan: Equatable, Sendable {
    /// HID tap for Control-Left/Right (must beat Mission Control).
    var wantsHID: Bool
    /// Session-tap event types (gestures and/or Command-Tab keys).
    var sessionEvents: [UInt32]

    var wantsSessionTap: Bool { !sessionEvents.isEmpty }
    var wantsAnyTap: Bool { wantsHID || wantsSessionTap }

    init(mode: SystemMotionMode) {
        wantsHID = mode.suppressDesktopMotion
        var events: [UInt32] = []
        if mode.suppressDesktopMotion {
            events.append(contentsOf: [29, 30])
        }
        if mode.commandTabEnabled {
            events.append(contentsOf: [
                CGEventType.keyDown.rawValue,
                CGEventType.keyUp.rawValue,
                CGEventType.flagsChanged.rawValue,
            ])
        }
        sessionEvents = events
    }
}
