import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "EventTapHost")

/// Owns CGEvent tap create / enable / teardown and the weak context box.
final class EventTapHost {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private final class Context {
        weak var host: EventTapHost?
    }

    private let context = Context()
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var installedSessionEvents: [UInt32] = []
    private var installedHID = false

    var handler: Handler?
    var onTapDisabled: (() -> Void)?

    var isRunning: Bool { gestureTap != nil || keyTap != nil }

    init() {
        context.host = self
    }

    deinit {
        context.host = nil
        tearDown()
    }

    func start(mode: SystemMotionMode) {
        guard mode.wantsTaps else {
            stop()
            return
        }

        var sessionEvents: [UInt32] = []
        if mode.commandTabEnabled || mode.suppressDesktopMotion {
            sessionEvents.append(contentsOf: [
                CGEventType.keyDown.rawValue,
                CGEventType.keyUp.rawValue,
                CGEventType.flagsChanged.rawValue,
            ])
        }
        if mode.suppressDesktopMotion {
            sessionEvents.append(contentsOf: [29, 30])
        }
        let wantHID = mode.suppressDesktopMotion

        if isRunning {
            if sessionEvents == installedSessionEvents, wantHID == installedHID {
                return
            }
            tearDown()
        }

        guard AXIsProcessTrusted() else { return }

        let userInfo = Unmanaged.passUnretained(context).toOpaque()
        guard !sessionEvents.isEmpty,
              let gesture = installTap(
                  location: .cgSessionEventTap,
                  events: sessionEvents,
                  userInfo: userInfo
              )
        else {
            return
        }
        gestureTap = gesture.tap
        gestureSource = gesture.source
        installedSessionEvents = sessionEvents

        if wantHID {
            // Mission Control handles Control-Left/Right before a session tap runs.
            // The HID tap sees the key first and can drop it before that shortcut starts the slide.
            if let keys = installTap(
                location: .cghidEventTap,
                events: [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue],
                userInfo: userInfo
            ) {
                keyTap = keys.tap
                keySource = keys.source
                installedHID = true
            } else {
                installedHID = false
                log.error("Could not create the keyboard tap for Control-Left/Right")
            }
        } else {
            installedHID = false
        }
    }

    func stop() {
        tearDown()
    }

    private func tearDown() {
        for source in [gestureSource, keySource] {
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        for tap in [gestureTap, keyTap] {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
        }
        gestureTap = nil
        gestureSource = nil
        keyTap = nil
        keySource = nil
        installedSessionEvents = []
        installedHID = false
    }

    private func installTap(
        location: CGEventTapLocation,
        events: [UInt32],
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
            callback: Self.callback,
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

    private func reenableTaps() {
        if let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: true)
        }
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: true)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<Context>.fromOpaque(userInfo).takeUnretainedValue()
        guard let host = context.host else {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            host.reenableTaps()
            host.onTapDisabled?()
            log.error("Event tap was disabled (\(type.rawValue, privacy: .public)); re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard let handler = host.handler else {
            return Unmanaged.passUnretained(event)
        }
        if let forwarded = handler(type, event) {
            return Unmanaged.passUnretained(forwarded)
        }
        return nil
    }
}
