import CoreGraphics
import Foundation

/// Owns the session and HID CGEvent taps driven by a MotionTapPlan.
final class EventTapHost {
    struct InstallResult {
        /// False when a required session tap could not be created.
        var ok: Bool
        /// True when the plan asked for HID and that tap failed (session may still be up).
        var hidFailed: Bool
    }

    private(set) var installedPlan: MotionTapPlan?
    private var sessionTap: CFMachPort?
    private var sessionSource: CFRunLoopSource?
    private var hidTap: CFMachPort?
    private var hidSource: CFRunLoopSource?

    var hasAnyTap: Bool { sessionTap != nil || hidTap != nil }

    /// Install taps for `plan`. Tears down any existing taps first.
    @discardableResult
    func install(
        plan: MotionTapPlan,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> InstallResult {
        tearDown()
        guard plan.wantsAnyTap else { return InstallResult(ok: false, hidFailed: false) }

        if plan.wantsSessionTap {
            guard let session = Self.installTap(
                location: .cgSessionEventTap,
                events: plan.sessionEvents,
                callback: callback,
                userInfo: userInfo
            ) else {
                return InstallResult(ok: false, hidFailed: false)
            }
            sessionTap = session.tap
            sessionSource = session.source
        }

        var hidFailed = false
        // Mission Control handles Control-Left/Right before a session tap runs.
        // The HID tap sees the key first and can drop it before that shortcut starts the slide.
        if plan.wantsHID {
            if let keys = Self.installTap(
                location: .cghidEventTap,
                events: [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue],
                callback: callback,
                userInfo: userInfo
            ) {
                hidTap = keys.tap
                hidSource = keys.source
            } else {
                hidFailed = true
            }
        }

        installedPlan = plan
        return InstallResult(ok: true, hidFailed: hidFailed)
    }

    func reenable() {
        if let sessionTap {
            CGEvent.tapEnable(tap: sessionTap, enable: true)
        }
        if let hidTap {
            CGEvent.tapEnable(tap: hidTap, enable: true)
        }
    }

    func tearDown() {
        for source in [sessionSource, hidSource] {
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        for tap in [sessionTap, hidTap] {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
        }
        sessionTap = nil
        sessionSource = nil
        hidTap = nil
        hidSource = nil
        installedPlan = nil
    }

    private static func installTap(
        location: CGEventTapLocation,
        events: [UInt32],
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> (tap: CFMachPort, source: CFRunLoopSource)? {
        var mask: CGEventMask = 0
        for raw in events {
            mask |= CGEventMask(1) << CGEventMask(raw)
        }
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return nil
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return (tap, source)
    }
}
