import AppKit
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "DockSwipe")

/// Performs a real Space transition by synthesizing a trackpad dock-swipe.
///
/// On modern macOS, `CGSManagedDisplaySetCurrentSpace` only updates bookkeeping.
/// The Dock still honors the trackpad gesture pathway (same approach as
/// dockswipe / InstantSpaceSwitcher / Mac Mouse Fix). Requires Accessibility.
enum DockSwipeSwitcher {
    private static let eventTypeField = CGEventField(rawValue: 55)!
    private static let field41 = CGEventField(rawValue: 41)!
    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!
    private static let weirdFloatField = CGEventField(rawValue: 119)!
    private static let swipeMotionField = CGEventField(rawValue: 123)!
    private static let swipeProgressField = CGEventField(rawValue: 124)!
    private static let swipeVelocityXField = CGEventField(rawValue: 129)!
    private static let swipeVelocityYField = CGEventField(rawValue: 130)!
    private static let gesturePhaseField = CGEventField(rawValue: 132)!
    private static let gesturePhaseAliasField = CGEventField(rawValue: 134)!
    private static let progressBitsField = CGEventField(rawValue: 135)!
    private static let invertedField = CGEventField(rawValue: 136)!
    private static let weirdFloatAliasField = CGEventField(rawValue: 139)!
    private static let axisAliasField = CGEventField(rawValue: 165)!

    private static let dockControlEvent: Double = 30
    private static let gestureEvent: Double = 29
    private static let dockSwipeHIDType: Double = 23
    private static let horizontalAxis: Double = 1
    /// IEEE-754 denormal whose bit pattern is 0x1 (horizontal axis marker).
    private static let horizontalWeirdFloat = Double(Float(bitPattern: 1))

    private static let phaseBegan = 1
    private static let phaseChanged = 2
    private static let phaseEnded = 4

    enum Direction {
        case left
        case right
    }

    /// Stamped on events Altitude posts so the motion tap does not treat them as a finger swipe.
    static let syntheticMarker: Int64 = 0x414C5444

    private static let gestureQueue = DispatchQueue(label: "com.altitude.dockswipe", qos: .userInteractive)

    static func isOwnEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
    }

    struct HorizontalSwipe {
        /// Signed travel already in Dock Space-switch coordinates (natural scrolling applied).
        let progress: Double
        let direction: Direction?
        let began: Bool
        let ended: Bool
    }

    /// Dock-control and gesture markers live in field 55; the public event type is not always set.
    private static func kind(of event: CGEvent) -> UInt32 {
        let stamped = UInt32(event.getDoubleValueField(eventTypeField))
        if stamped == UInt32(dockControlEvent) || stamped == UInt32(gestureEvent) {
            return stamped
        }
        return event.type.rawValue
    }

    /// A real or synthetic horizontal Space swipe, or nil for Mission Control and other gestures.
    ///
    /// Progress uses the Dock's effective Space direction, so natural scrolling is already
    /// reflected — do not flip it again from the scroll-direction preference.
    static func horizontalSwipe(in event: CGEvent) -> HorizontalSwipe? {
        guard kind(of: event) == UInt32(dockControlEvent),
              event.getDoubleValueField(gestureHIDTypeField) == dockSwipeHIDType,
              event.getDoubleValueField(swipeMotionField) == horizontalAxis
        else {
            return nil
        }
        let phase = Int(event.getDoubleValueField(gesturePhaseField))
        let progress = event.getDoubleValueField(swipeProgressField)
        let velocity = event.getDoubleValueField(swipeVelocityXField)
        // Prefer progress; fall back to velocity near the start when progress is still zero.
        let sample = abs(progress) > 0.0001 ? progress : velocity
        let direction: Direction?
        if sample > 0.0001 {
            direction = .right
        } else if sample < -0.0001 {
            direction = .left
        } else {
            direction = nil
        }
        return HorizontalSwipe(
            progress: sample,
            direction: direction,
            began: phase & phaseBegan != 0,
            ended: phase & phaseEnded != 0
        )
    }

    static func isGestureCompanion(_ event: CGEvent) -> Bool {
        kind(of: event) == UInt32(gestureEvent)
    }

    private static let smoothFrameCount = 24
    private static let smoothFrameInterval: TimeInterval = 0.008
    private static let smoothStepGap: TimeInterval = 0.28

    /// Time spent posting gesture frames; the Dock's own animation comes on top.
    static func estimatedDuration(steps: Int, instant: Bool) -> TimeInterval {
        guard !instant, steps > 0 else { return 0 }
        let perStep = Double(smoothFrameCount) * smoothFrameInterval
        return Double(steps) * perStep + Double(steps - 1) * smoothStepGap
    }

    /// One gesture per space, posted back-to-back. A gap lets the desktop in
    /// between paint; a single faster fling still only moves one space.
    /// Posting happens asynchronously; failures are logged.
    static func swipe(_ direction: Direction, steps: Int, instant: Bool) {
        guard steps > 0 else { return }

        gestureQueue.async {
            if instant {
                guard postInstantSwipe(direction: direction, spaces: steps) else {
                    log.error("Failed posting direct dock-swipe (\(steps) space(s))")
                    return
                }
            } else {
                for step in 0..<steps {
                    guard postSmoothSwipe(direction: direction) else {
                        log.error("Failed posting dock-swipe (step \(step + 1)/\(steps))")
                        return
                    }
                    if step + 1 < steps {
                        usleep(useconds_t(smoothStepGap * 1_000_000))
                    }
                }
            }
        }
    }

    /// One space, paced like a real trackpad swipe so the system slide stays continuous.
    private static func postSmoothSwipe(direction: Direction) -> Bool {
        let sign: Double = direction == .right ? 1 : -1
        let frameCount = smoothFrameCount
        let totalOffset = 1.35 * sign
        let delta = totalOffset / Double(frameCount)
        var origin = 0.0

        for frame in 0..<frameCount {
            let phase: Int
            if frame == 0 {
                phase = phaseBegan
            } else if frame + 1 == frameCount {
                phase = phaseEnded
            } else {
                phase = phaseChanged
            }
            origin += delta
            let exitSpeed = phase == phaseEnded ? delta * 90 : 0
            guard postFrame(offset: origin, phase: phase, exitSpeed: exitSpeed) else {
                return false
            }
            usleep(useconds_t(smoothFrameInterval * 1_000_000))
        }
        return true
    }

    /// One committed space per gesture. Post every hop immediately so the
    /// desktops in between never get a frame.
    private static func postInstantSwipe(direction: Direction, spaces: Int) -> Bool {
        let sign: Double = direction == .right ? 1 : -1
        for _ in 0..<max(spaces, 1) {
            guard postFrame(offset: 0, phase: phaseBegan, exitSpeed: 0),
                  postFrame(offset: 2 * sign, phase: phaseEnded, exitSpeed: 1000 * sign)
            else {
                return false
            }
        }
        return true
    }

    private static func postFrame(offset: Double, phase: Int, exitSpeed: Double) -> Bool {
        guard let companion = CGEvent(source: nil),
              let dock = CGEvent(source: nil)
        else {
            return false
        }

        companion.setDoubleValueField(eventTypeField, value: gestureEvent)
        companion.setDoubleValueField(field41, value: 33231)

        dock.setDoubleValueField(eventTypeField, value: dockControlEvent)
        dock.setDoubleValueField(gestureHIDTypeField, value: dockSwipeHIDType)
        dock.setDoubleValueField(gesturePhaseField, value: Double(phase))
        dock.setDoubleValueField(gesturePhaseAliasField, value: Double(phase))
        dock.setDoubleValueField(swipeProgressField, value: offset)

        var offsetFloat = Float(offset)
        var offsetBits: UInt32 = 0
        withUnsafeMutableBytes(of: &offsetFloat) { src in
            withUnsafeMutableBytes(of: &offsetBits) { dst in
                dst.copyBytes(from: src)
            }
        }
        dock.setIntegerValueField(progressBitsField, value: Int64(offsetBits))
        dock.setDoubleValueField(field41, value: 33231)

        dock.setDoubleValueField(weirdFloatField, value: horizontalWeirdFloat)
        dock.setDoubleValueField(weirdFloatAliasField, value: horizontalWeirdFloat)
        dock.setDoubleValueField(swipeMotionField, value: horizontalAxis)
        dock.setDoubleValueField(axisAliasField, value: horizontalAxis)
        dock.setIntegerValueField(invertedField, value: 0)

        if phase == phaseEnded {
            dock.setDoubleValueField(swipeVelocityXField, value: exitSpeed)
            dock.setDoubleValueField(swipeVelocityYField, value: 0)
        }

        dock.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        companion.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)

        // Dock control first, then companion gesture marker (dockswipe / MMF order).
        dock.post(tap: .cgSessionEventTap)
        companion.post(tap: .cgSessionEventTap)
        return true
    }
}
