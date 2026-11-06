import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "EventTap")

/// Owns the session and HID CGEvent taps driven by a MotionTapPlan.
/// Taps run on a dedicated thread so delivery does not wait on the main run loop.
final class EventTapHost: @unchecked Sendable {
    struct InstallResult {
        /// False when a required session tap could not be created.
        var ok: Bool
        /// True when the plan asked for HID and that tap failed (session may still be up).
        var hidFailed: Bool
    }

    /// Upper bound for sync work posted to the tap thread (install / tearDown).
    private static let syncTimeout: DispatchTimeInterval = .seconds(2)

    private(set) var installedPlan: MotionTapPlan?
    private var sessionTap: CFMachPort?
    private var sessionSource: CFRunLoopSource?
    private var hidTap: CFMachPort?
    private var hidSource: CFRunLoopSource?

    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var keepAlivePort: NSMachPort?
    private var stopRequested = false
    private let gate = NSCondition()

    var hasAnyTap: Bool { sessionTap != nil || hidTap != nil }

    deinit {
        tearDown()
        stopThread()
    }

    /// Install taps for `plan`. Tears down any existing taps first.
    /// Blocks until the tap thread has finished installing (or failed / timed out).
    @discardableResult
    func install(
        plan: MotionTapPlan,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> InstallResult {
        ensureThread()
        return syncOnTapThread(
            onTimeout: InstallResult(ok: false, hidFailed: false)
        ) {
            self.removeTapsOnTapThread()
            guard plan.wantsAnyTap else {
                self.installedPlan = nil
                return InstallResult(ok: false, hidFailed: false)
            }

            if plan.wantsSessionTap {
                guard let session = Self.installTap(
                    location: .cgSessionEventTap,
                    events: plan.sessionEvents,
                    callback: callback,
                    userInfo: userInfo
                ) else {
                    self.installedPlan = nil
                    return InstallResult(ok: false, hidFailed: false)
                }
                self.sessionTap = session.tap
                self.sessionSource = session.source
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
                    self.hidTap = keys.tap
                    self.hidSource = keys.source
                } else {
                    hidFailed = true
                }
            }

            self.installedPlan = plan
            return InstallResult(ok: true, hidFailed: hidFailed)
        }
    }

    func reenable() {
        let work = { [self] in
            if let sessionTap {
                CGEvent.tapEnable(tap: sessionTap, enable: true)
            }
            if let hidTap {
                CGEvent.tapEnable(tap: hidTap, enable: true)
            }
        }
        if isOnTapThread {
            work()
        } else {
            asyncOnTapThread(work)
        }
    }

    /// Removes taps on the tap thread and waits until that finishes (or times out).
    func tearDown() {
        gate.lock()
        let hasThread = thread != nil
        let loop = runLoop
        gate.unlock()

        guard hasThread, loop != nil else {
            // No live tap thread — do not remove sources from the caller's run loop.
            abandonTapsWithoutRunLoop()
            return
        }
        _ = syncOnTapThread(onTimeout: ()) {
            self.removeTapsOnTapThread()
        }
    }

    /// Publish work onto the tap thread's run loop (non-blocking).
    func asyncOnTapThread(_ body: @escaping () -> Void) {
        ensureThread()
        guard let runLoop else {
            return
        }
        if CFEqual(CFRunLoopGetCurrent(), runLoop) {
            body()
            return
        }
        let mode = CFRunLoopMode.commonModes.rawValue as CFString
        CFRunLoopPerformBlock(runLoop, mode) {
            body()
        }
        CFRunLoopWakeUp(runLoop)
    }

    private var isOnTapThread: Bool {
        guard let runLoop else { return false }
        return CFEqual(CFRunLoopGetCurrent(), runLoop)
    }

    private func ensureThread() {
        gate.lock()
        if thread != nil {
            while runLoop == nil, !stopRequested {
                gate.wait()
            }
            gate.unlock()
            return
        }
        stopRequested = false
        let worker = Thread { [weak self] in
            self?.threadMain()
        }
        worker.name = "Altitude.EventTap"
        thread = worker
        gate.unlock()
        worker.start()

        gate.lock()
        while runLoop == nil, !stopRequested {
            gate.wait()
        }
        gate.unlock()
    }

    private func threadMain() {
        let port = NSMachPort()
        RunLoop.current.add(port, forMode: .default)
        gate.lock()
        keepAlivePort = port
        runLoop = CFRunLoopGetCurrent()
        gate.broadcast()
        gate.unlock()

        CFRunLoopRun()

        gate.lock()
        if let port = keepAlivePort {
            RunLoop.current.remove(port, forMode: .default)
        }
        keepAlivePort = nil
        runLoop = nil
        thread = nil
        gate.broadcast()
        gate.unlock()
    }

    private func stopThread() {
        gate.lock()
        guard let runLoop else {
            thread = nil
            gate.unlock()
            return
        }
        stopRequested = true
        gate.unlock()
        let mode = CFRunLoopMode.commonModes.rawValue as CFString
        CFRunLoopPerformBlock(runLoop, mode) {
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)

        gate.lock()
        let deadline = Date().addingTimeInterval(2)
        while self.runLoop != nil {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            _ = gate.wait(until: deadline)
        }
        if self.runLoop != nil {
            log.error("Timed out waiting for event-tap thread to stop")
        }
        thread = nil
        gate.unlock()
    }

    private func syncOnTapThread<T>(onTimeout: @autoclosure () -> T, _ body: @escaping () -> T) -> T {
        if isOnTapThread {
            return body()
        }
        ensureThread()
        guard let runLoop else {
            log.error("Event-tap thread has no run loop; skipping sync work")
            return onTimeout()
        }
        let done = DispatchSemaphore(value: 0)
        var result: T?
        let mode = CFRunLoopMode.commonModes.rawValue as CFString
        CFRunLoopPerformBlock(runLoop, mode) {
            result = body()
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        if done.wait(timeout: .now() + Self.syncTimeout) == .timedOut {
            log.error("Timed out waiting for event-tap thread sync work")
            return onTimeout()
        }
        guard let result else {
            log.error("Event-tap sync completed without a result")
            return onTimeout()
        }
        return result
    }

    /// Invalidate ports and drop refs when the tap run loop is already gone.
    private func abandonTapsWithoutRunLoop() {
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

    private func removeTapsOnTapThread() {
        let loop = CFRunLoopGetCurrent()
        for source in [sessionSource, hidSource] {
            if let source {
                CFRunLoopRemoveSource(loop, source, .commonModes)
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
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return (tap, source)
    }
}
