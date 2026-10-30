import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os.log

/// One Command-Tab entry. An app with two windows produces two of these.
private struct SwitchTarget {
    let app: NSRunningApplication
    let windowID: CGWindowID?
    let title: String
    let width: Double
    let height: Double

    func sameInstance(as other: SwitchTarget) -> Bool {
        app.processIdentifier == other.app.processIdentifier
            && title == other.title
            && abs(width - other.width) < 2
            && abs(height - other.height) < 2
    }
}

private let log = Logger(subsystem: "com.altitude.app", category: "SystemMotion")

/// Replaces animated Space changes from the trackpad, Control-Left/Right, Command-Tab,
/// and external activation of an already-running app on another Space.
///
/// macOS has no switch that turns off only those motions. A session tap drops the real
/// horizontal swipe before the Dock can slide, then posts one instant hop via SpaceService.
/// At the first or last Space on the active display the input is still swallowed but nothing
/// is posted, so the Dock edge bounce never runs. Control-Left/Right is swallowed at the HID
/// tap, before Mission Control's shortcut can start the slide. Command-Tab is handled here so
/// releasing Command does not play the system switcher. Activating a running app via Raycast,
/// Spotlight, Dock, or similar hops to that app's Space with no slide and leaves the window
/// there. Mission Control swipes are left alone.
/// Weak box so CGEvent tap callbacks no-op after the suppressor is released.
private final class MotionTapContext {
    weak var suppressor: SystemMotionSuppressor?
}

final class SystemMotionSuppressor: NSObject {
    private struct Session {
        var targets: [SwitchTarget]
        var index: Int
    }

    private let spaceService: SpaceService
    private let hud = AppSwitchHUD()
    private let tapContext = MotionTapContext()
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var didLogTapFailure = false

    private var swallowingSwipe = false
    private var postedForSwipe = false
    private var swipeDeadline = Date.distantPast
    private var swipePeak: Double = 0
    private var swipeDirection: DockSwipeSwitcher.Direction?

    private var session: Session?
    private var mru: [pid_t] = []
    private var pendingActivation: SwitchTarget?
    private var activationFallback: DispatchWorkItem?
    /// True while our own activate(_:) is raising an app, so appActivated does not re-enter.
    private var isActivatingInternally = false

    /// Accessibility calls that hang on a beachballed app must not block the keyboard tap.
    private let axTimeoutSeconds: Float = 0.1
    /// Finger must travel at least this far before a released swipe commits a Space change.
    private let swipeCommitThreshold: Double = 0.08

    private let tabKeyCode: Int64 = 48
    private let escapeKeyCode: Int64 = 53
    private let leftArrowKeyCode: Int64 = 123
    private let rightArrowKeyCode: Int64 = 124
    private let qKeyCode: Int64 = 12
    private let hKeyCode: Int64 = 4

    init(spaceService: SpaceService) {
        self.spaceService = spaceService
        super.init()
        tapContext.suppressor = self
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self)
        tapContext.suppressor = nil
        tearDownTaps()
    }

    func start() {
        guard gestureTap == nil, keyTap == nil else { return }
        guard AXIsProcessTrusted() else {
            logTapFailure("Accessibility is required to disable trackpad, Control-arrow, and Command-Tab motion")
            return
        }

        let userInfo = Unmanaged.passUnretained(tapContext).toOpaque()
        guard let gesture = installTap(
            location: .cgSessionEventTap,
            events: [
                CGEventType.keyDown.rawValue,
                CGEventType.keyUp.rawValue,
                CGEventType.flagsChanged.rawValue,
                29,
                30,
            ],
            userInfo: userInfo
        ) else {
            logTapFailure("Could not create the event tap that disables system motion")
            return
        }
        gestureTap = gesture.tap
        gestureSource = gesture.source

        // Mission Control handles Control-Left/Right before a session tap runs.
        // The HID tap sees the key first and can drop it before that shortcut starts the slide.
        if let keys = installTap(
            location: .cghidEventTap,
            events: [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue],
            userInfo: userInfo
        ) {
            keyTap = keys.tap
            keySource = keys.source
        } else {
            logTapFailure("Could not create the keyboard tap for Control-Left/Right")
        }

        didLogTapFailure = false
        log.info("System motion suppression is on")
    }

    func stop() {
        cancelSession()
        pendingActivation = nil
        activationFallback?.cancel()
        activationFallback = nil
        isActivatingInternally = false
        swallowingSwipe = false
        postedForSwipe = false
        swipePeak = 0
        swipeDirection = nil
        tearDownTaps()
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

    private func tearDownTaps() {
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
    }

    // MARK: - Tap

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<MotionTapContext>.fromOpaque(userInfo).takeUnretainedValue()
        guard let suppressor = context.suppressor else {
            return Unmanaged.passUnretained(event)
        }
        if let forwarded = suppressor.handle(type: type, event: event) {
            return Unmanaged.passUnretained(forwarded)
        }
        return nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let gestureTap {
                CGEvent.tapEnable(tap: gestureTap, enable: true)
            }
            if let keyTap {
                CGEvent.tapEnable(tap: keyTap, enable: true)
            }
            log.error("Event tap was disabled (\(type.rawValue, privacy: .public)); re-enabled")
            return event
        }

        if DockSwipeSwitcher.isOwnEvent(event) {
            return event
        }
        if swallowingSwipe, Date() > swipeDeadline {
            swallowingSwipe = false
            postedForSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }

        if let swipe = DockSwipeSwitcher.horizontalSwipe(in: event) {
            consume(swipe)
            return nil
        }
        if swallowingSwipe, DockSwipeSwitcher.isGestureCompanion(event) {
            return nil
        }
        return handleKeyboard(type: type, event: event)
    }

    /// Swallow the live gesture and only jump when the finger lifts past the commit threshold.
    /// That lets a reversed or aborted swipe cancel, matching Mission Control's habit.
    private func consume(_ swipe: DockSwipeSwitcher.HorizontalSwipe) {
        if swipe.began {
            postedForSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }
        swallowingSwipe = !swipe.ended
        swipeDeadline = Date().addingTimeInterval(1.5)

        let magnitude = abs(swipe.progress)
        if magnitude >= abs(swipePeak), let direction = swipe.direction {
            swipePeak = swipe.progress
            swipeDirection = direction
        }

        if swipe.ended {
            if !postedForSwipe,
               abs(swipePeak) >= swipeCommitThreshold,
               let direction = swipeDirection
            {
                postedForSwipe = true
                _ = spaceService.moveOneSpaceInstantly(direction: hopDirection(direction))
            }
            postedForSwipe = false
            swallowingSwipe = false
            swipePeak = 0
            swipeDirection = nil
        }
    }

    // MARK: - Command-Tab

    private func handleKeyboard(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .flagsChanged {
            if session != nil, !event.flags.contains(.maskCommand) {
                commitSession()
            }
            return event
        }

        if session != nil {
            return handleSwitcherKey(type: type, event: event)
        }

        if let direction = controlArrowDirection(type: type, event: event) {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                _ = spaceService.moveOneSpaceInstantly(direction: hopDirection(direction))
            }
            return nil
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)
        let extra = event.flags.contains(.maskAlternate) || event.flags.contains(.maskControl)

        guard command, !extra, keyCode == tabKeyCode else { return event }
        if type == .keyUp {
            return nil
        }
        guard type == .keyDown else { return event }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        let targets = switchTargets()
        guard targets.count >= 2 else { return event }
        session = Session(targets: targets, index: 0)
        moveSelection(by: shift ? -1 : 1)
        return nil
    }

    /// While the switcher is open, keys go to Altitude — not the frontmost app.
    /// Tab / arrows move, Escape cancels, Q quits and H hides the highlighted app.
    private func handleSwitcherKey(type: CGEventType, event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if let step = switcherArrowStep(keyCode: keyCode) {
            if type == .keyDown, !isRepeat {
                moveSelection(by: step)
            }
            return nil
        }

        if keyCode == escapeKeyCode {
            if type == .keyDown, !isRepeat {
                cancelSession()
            }
            return nil
        }

        let command = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)
        let extra = event.flags.contains(.maskAlternate) || event.flags.contains(.maskControl)

        if command, !extra, keyCode == tabKeyCode {
            if type == .keyDown, !isRepeat {
                moveSelection(by: shift ? -1 : 1)
            }
            return nil
        }

        if command, !extra, keyCode == qKeyCode {
            if type == .keyDown, !isRepeat {
                quitHighlighted()
            }
            return nil
        }

        if command, !extra, keyCode == hKeyCode {
            if type == .keyDown, !isRepeat {
                hideHighlighted()
            }
            return nil
        }

        // Drop every other key so Command-Q / Command-W cannot hit the app underneath.
        return nil
    }

    private func switcherArrowStep(keyCode: Int64) -> Int? {
        switch keyCode {
        case leftArrowKeyCode:
            return -1
        case rightArrowKeyCode:
            return 1
        default:
            return nil
        }
    }

    private func moveSelection(by delta: Int) {
        guard var current = session else { return }
        let count = current.targets.count
        guard count >= 2, delta != 0 else {
            if count < 2 { cancelSession() }
            return
        }
        let wrapped = (current.index + delta % count + count) % count
        current.index = wrapped
        session = current
        hud.show(targets: current.targets, selectedIndex: current.index)
    }

    /// Control-Left/Right is the system "move a space" shortcut. Command, Option, and Shift stay free.
    private func controlArrowDirection(type: CGEventType, event: CGEvent) -> DockSwipeSwitcher.Direction? {
        guard type == .keyDown || type == .keyUp else { return nil }
        let flags = event.flags
        guard flags.contains(.maskControl),
              !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift)
        else {
            return nil
        }
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case leftArrowKeyCode:
            return .left
        case rightArrowKeyCode:
            return .right
        default:
            return nil
        }
    }

    private func hopDirection(_ direction: DockSwipeSwitcher.Direction) -> SpaceHopDirection {
        switch direction {
        case .left:
            return .previous
        case .right:
            return .next
        }
    }

    private func commitSession() {
        guard let session else { return }
        self.session = nil
        hud.hide()
        guard session.targets.indices.contains(session.index), session.index != 0 else { return }
        let target = session.targets[session.index]
        let spaces = target.windowID.map { CGSPrivate.spaceIDs(forWindow: $0) } ?? []
        switch spaceService.switchInstantly(toPreferredSpaceAmong: spaces) {
        case .posted(let steps):
            // Let the instant swipe land before activation, or macOS starts its own slide.
            let delay = 0.08 + 0.06 * Double(max(steps, 1))
            armActivation(of: target, after: delay)
        case .alreadyThere, .otherDisplay, .unavailable:
            activate(target)
        }
    }

    private func cancelSession() {
        session = nil
        hud.hide()
    }

    private func quitHighlighted() {
        guard let session, session.targets.indices.contains(session.index) else {
            cancelSession()
            return
        }
        let target = session.targets[session.index]
        cancelSession()
        _ = target.app.terminate()
    }

    private func hideHighlighted() {
        guard let session, session.targets.indices.contains(session.index) else {
            cancelSession()
            return
        }
        let target = session.targets[session.index]
        cancelSession()
        _ = target.app.hide()
    }

    private func armActivation(of target: SwitchTarget, after delay: TimeInterval) {
        pendingActivation = target
        activationFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pendingActivation, pending.sameInstance(as: target) else { return }
            self.pendingActivation = nil
            self.activate(target)
        }
        activationFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func activate(_ target: SwitchTarget) {
        // Raise first, then again after activate(). Activation focuses the app's main
        // window on its own, which is why an Outlook message was opening the inbox.
        isActivatingInternally = true
        focus(target)
        _ = target.app.activate(from: .current, options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isActivatingInternally = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.focus(target)
        }
    }

    /// Main window if Accessibility marked one; otherwise the first listed window.
    private func preferredTarget(for app: NSRunningApplication) -> SwitchTarget? {
        let windows = userWindows(for: app)
        guard let preferred = windows.first(where: \.main) ?? windows.first else { return nil }
        return makeTarget(app: app, window: preferred)
    }

    /// Instant hop when an external activator focuses a running app on another same-display Space.
    private func hopForExternalActivation(of app: NSRunningApplication) {
        guard let target = preferredTarget(for: app) else { return }
        let spaces = target.windowID.map { CGSPrivate.spaceIDs(forWindow: $0) } ?? []
        switch spaceService.switchInstantly(toPreferredSpaceAmong: spaces) {
        case .posted(let steps):
            let delay = 0.08 + 0.06 * Double(max(steps, 1))
            armActivation(of: target, after: delay)
        case .alreadyThere:
            activate(target)
        case .otherDisplay, .unavailable:
            break
        }
    }

    /// Raise the selected window, matching the accessibility window by id, then by title and size.
    private func focus(_ target: SwitchTarget) {
        guard AXIsProcessTrusted(), let window = axWindow(matching: target) else { return }
        let appElement = axApplication(pid: target.app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func axWindow(matching target: SwitchTarget) -> AXUIElement? {
        let appElement = axApplication(pid: target.app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return nil
        }
        let described = windows.map { element in
            (element: element, title: axString(element, kAXTitleAttribute as String), size: axSize(element))
        }
        if let windowID = target.windowID, windowID != 0 {
            if let match = described.first(where: { axWindowID($0.element) == windowID }) {
                return match.element
            }
        }
        let appName = (target.app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = described.filter { item in
            guard let size = item.size else { return false }
            let sizeMatches = abs(size.width - target.width) < 4 && abs(size.height - target.height) < 4
            let titleMatches = !target.title.isEmpty && item.title == target.title
            // After merge, the strip may keep a stronger CG title while AX still reports empty / app name.
            return sizeMatches && (
                titleMatches
                    || isWeakTitle(item.title, appName: appName)
                    || isWeakTitle(target.title, appName: appName)
            )
        }
        if let exact = titled.first(where: { $0.title == target.title }) {
            return exact.element
        }
        return titled.first?.element
    }

    private func axApplication(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axTimeoutSeconds)
        return element
    }

    /// Frontmost window first, then other apps in MRU order, then the rest of the
    /// frontmost app's windows — so a single Command-Tab lands on the previous app.
    private func switchTargets() -> [SwitchTarget] {
        let apps = orderedApps()
        guard let front = apps.first else { return [] }

        var frontWindows = userWindows(for: front)
        let primaryIndex = frontWindows.firstIndex(where: \.main) ?? frontWindows.startIndex
        let primary = frontWindows.isEmpty ? nil : frontWindows.remove(at: primaryIndex)

        var targets: [SwitchTarget] = []
        var appsWithWindows = Set<pid_t>()

        if let primary {
            appsWithWindows.insert(front.processIdentifier)
            targets.append(makeTarget(app: front, window: primary))
        }

        for app in apps.dropFirst() {
            let windows = userWindows(for: app)
            guard !windows.isEmpty else { continue }
            appsWithWindows.insert(app.processIdentifier)
            for window in windows {
                targets.append(makeTarget(app: app, window: window))
            }
        }

        if !frontWindows.isEmpty {
            appsWithWindows.insert(front.processIdentifier)
            for window in frontWindows {
                targets.append(makeTarget(app: front, window: window))
            }
        }

        for app in apps where !appsWithWindows.contains(app.processIdentifier) {
            targets.append(SwitchTarget(
                app: app,
                windowID: nil,
                title: app.localizedName ?? "Application",
                width: 0,
                height: 0
            ))
        }
        return targets
    }

    private func makeTarget(app: NSRunningApplication, window: ListedWindow) -> SwitchTarget {
        let title = window.title.isEmpty ? (app.localizedName ?? "Application") : window.title
        return SwitchTarget(
            app: app,
            windowID: window.id,
            title: title,
            width: window.width,
            height: window.height
        )
    }

    private struct ListedWindow {
        let id: CGWindowID?
        let title: String
        let width: Double
        let height: Double
        var main: Bool = false
    }

    /// Empty, or the app's localized name — too generic to treat as a distinct window identity.
    private func isWeakTitle(_ title: String, appName: String) -> Bool {
        if title.isEmpty { return true }
        return !appName.isEmpty && title == appName
    }

    /// Prefer a specific title over empty / the bare app name when collapsing twins.
    private func preferredTitle(_ a: String, _ b: String, appName: String) -> String {
        let aWeak = isWeakTitle(a, appName: appName)
        let bWeak = isWeakTitle(b, appName: appName)
        if aWeak && !bWeak { return b }
        if bWeak && !aWeak { return a }
        if a.isEmpty, !b.isEmpty { return b }
        return a
    }

    private func preferredWindowID(_ a: CGWindowID?, _ b: CGWindowID?) -> CGWindowID? {
        if let a, a != 0 { return a }
        if let b, b != 0 { return b }
        return nil
    }

    private func sameListedSize(_ a: ListedWindow, _ b: ListedWindow) -> Bool {
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// Same CG id, or same size with equal / weak titles — not two strong different titles.
    private func isSameListedWindow(_ a: ListedWindow, _ b: ListedWindow, appName: String) -> Bool {
        if let left = a.id, let right = b.id, left != 0, left == right {
            return true
        }
        guard sameListedSize(a, b) else { return false }
        if a.title == b.title { return true }
        return isWeakTitle(a.title, appName: appName) || isWeakTitle(b.title, appName: appName)
    }

    private func collapseListed(_ existing: ListedWindow, with other: ListedWindow, appName: String) -> ListedWindow {
        ListedWindow(
            id: preferredWindowID(existing.id, other.id),
            title: preferredTitle(existing.title, other.title, appName: appName),
            width: existing.width,
            height: existing.height,
            main: existing.main || other.main
        )
    }

    /// Accessibility covers the current Space; the window-server list adds windows on other Spaces.
    private func userWindows(for app: NSRunningApplication) -> [ListedWindow] {
        let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ax = accessibilityWindows(for: app)
        let cg = dedupe(cgWindows(pid: app.processIdentifier, appName: appName), appName: appName)
        return mergeWindows(ax: ax, cg: cg, appName: appName)
    }

    private func mergeWindows(ax: [ListedWindow], cg: [ListedWindow], appName: String) -> [ListedWindow] {
        var merged = ax
        // Accessibility already omitted panels on this Space; CG still lists some (Rex Settings).
        // Trust AX for the active Space; only append CG windows that live strictly elsewhere.
        let activeSpace = ax.isEmpty ? nil : CGSPrivate.activeSpaceID()
        for window in cg {
            if let index = merged.firstIndex(where: { isSameListedWindow($0, window, appName: appName) }) {
                // Keep AX order / main; absorb the stronger title and best id from CG.
                merged[index] = collapseListed(merged[index], with: window, appName: appName)
                continue
            }
            if let activeSpace, let id = window.id {
                let spaces = CGSPrivate.spaceIDs(forWindow: id)
                if spaces.contains(activeSpace) {
                    continue
                }
            }
            merged.append(window)
        }
        return merged
    }

    private func accessibilityWindows(for app: NSRunningApplication) -> [ListedWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let axApp = axApplication(pid: app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return []
        }
        // Do not apply the Electron helper filter here: Accessibility already omits most of
        // those, and an untitled real window of 500×500 would look the same.
        return windows.compactMap { element in
            let role = axString(element, kAXRoleAttribute as String)
            guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }
            let subrole = axString(element, kAXSubroleAttribute as String)
            if subrole == "AXUnknown" || subrole == "AXSystemDialog" { return nil }
            guard let size = axSize(element) else { return nil }
            guard size.width >= 160, size.height >= 100 else { return nil }
            let title = axString(element, kAXTitleAttribute as String)
            let id = axWindowID(element)
            return ListedWindow(
                id: id == 0 ? nil : id,
                title: title,
                width: size.width,
                height: size.height,
                main: axBool(element, kAXMainAttribute as String)
            )
        }
        .sorted { $0.main && !$1.main }
    }

    /// Window-server list. Includes off-Space windows and drops Electron's untitled / app-named copies.
    private func cgWindows(pid: pid_t, appName: String) -> [ListedWindow] {
        guard let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var seen = Set<CGWindowID>()
        let candidates: [(ListedWindow, Bool)] = info.compactMap { dict in
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { return nil }
            guard let owner = dict[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid else {
                return nil
            }
            guard let number = dict[kCGWindowNumber as String] as? NSNumber else { return nil }
            let windowID = number.uint32Value
            guard seen.insert(windowID).inserted else { return nil }
            let bounds = dict[kCGWindowBounds as String] as? [String: Any]
            let width = (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
            guard width >= 160, height >= 100 else { return nil }
            let title = ((dict[kCGWindowName as String] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let onscreen = (dict[kCGWindowIsOnscreen as String] as? Bool) ?? false
            if isHiddenHelper(width: width, height: height, title: title, onscreen: onscreen, appName: appName) {
                return nil
            }
            // Prefs chrome some apps publish to CG without exposing it to Accessibility (Rex).
            if !appName.isEmpty, title == "\(appName) Settings" { return nil }
            // Tiny untitled / app-named surfaces are not user windows.
            if isWeakTitle(title, appName: appName), width < 480 || height < 320 { return nil }
            return (ListedWindow(id: windowID, title: title, width: width, height: height, main: onscreen), onscreen)
        }
        let hasOnscreen = candidates.contains(where: \.1)
        return candidates.compactMap { window, onscreen in
            if hasOnscreen, !onscreen, isWeakTitle(window.title, appName: appName) { return nil }
            return window
        }
    }

    /// Same size with equal or weak titles means one window on the window-server list.
    /// Teams (and similar) publish twins there — often one empty / app-named and one specific.
    private func dedupe(_ windows: [ListedWindow], appName: String) -> [ListedWindow] {
        var kept: [ListedWindow] = []
        for window in windows {
            if let index = kept.firstIndex(where: { isSameListedWindow($0, window, appName: appName) }) {
                kept[index] = collapseListed(kept[index], with: window, appName: appName)
            } else {
                kept.append(window)
            }
        }
        return kept
    }

    /// Arc/Teams keep offscreen 500×500 / 800×600 helpers; title is often empty or just the app name.
    private func isHiddenHelper(
        width: Double,
        height: Double,
        title: String,
        onscreen: Bool,
        appName: String
    ) -> Bool {
        guard isWeakTitle(title, appName: appName) else { return false }
        if onscreen { return false }
        return (width == 500 && height == 500) || (width == 800 && height == 600)
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return "" }
        return ((ref as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return false }
        return (ref as? Bool) ?? false
    }

    private func axSize(_ element: AXUIElement) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID()
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(ref as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func axWindowID(_ element: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success else { return 0 }
        return id
    }

    private func orderedApps() -> [NSRunningApplication] {
        var ordered: [NSRunningApplication] = []
        var seen = Set<pid_t>()
        func consider(_ app: NSRunningApplication) {
            guard app.activationPolicy == .regular, !app.isTerminated else { return }
            if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
            guard seen.insert(app.processIdentifier).inserted else { return }
            ordered.append(app)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            consider(front)
        }
        for pid in mru {
            if let app = NSRunningApplication(processIdentifier: pid) {
                consider(app)
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            consider(app)
        }
        return ordered
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        guard app.activationPolicy == .regular, !app.isTerminated else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        mru.removeAll { $0 == app.processIdentifier }
        mru.insert(app.processIdentifier, at: 0)

        // Hop only while suppression is running. Skip Command-Tab and our own activates.
        guard gestureTap != nil else { return }
        if session != nil || isActivatingInternally || pendingActivation != nil { return }
        hopForExternalActivation(of: app)
    }

    private func logTapFailure(_ message: StaticString) {
        guard !didLogTapFailure else { return }
        didLogTapFailure = true
        log.error("\(message, privacy: .public)")
    }
}

/// Still row of running apps shown while Command is held. It does not fade or slide.
private final class AppSwitchHUD {
    private let panel: NSPanel
    private let effect: NSVisualEffectView
    private let nameField = NSTextField(labelWithString: "")
    private let iconHost = NSView()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.worksWhenModal = true

        effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        iconHost.wantsLayer = false
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = .labelColor
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingTail
        nameField.drawsBackground = false
        nameField.isBezeled = false
        nameField.isEditable = false
        effect.addSubview(iconHost)
        effect.addSubview(nameField)
    }

    func show(targets: [SwitchTarget], selectedIndex: Int) {
        guard !targets.isEmpty else {
            hide()
            return
        }
        let index = min(max(selectedIndex, 0), targets.count - 1)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let maxWidth = (screen?.visibleFrame.width ?? 1280) - 48
        let paddingX: CGFloat = 16
        let paddingTop: CGFloat = 14
        let nameGap: CGFloat = 8
        let nameHeight: CGFloat = 18
        let paddingBottom: CGFloat = 12
        let iconGap: CGFloat = 8
        let count = CGFloat(targets.count)
        let gaps = iconGap * max(count - 1, 0)
        let available = max(maxWidth - paddingX * 2 - gaps, count)
        let iconSide = min(64, floor(available / count))
        let rowWidth = count * iconSide + gaps
        let width = min(maxWidth, rowWidth + paddingX * 2)
        let height = paddingTop + iconSide + nameGap + nameHeight + paddingBottom

        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: width, height: height)
        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        )
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true, animate: false)

        let rowX = (width - rowWidth) / 2
        iconHost.frame = NSRect(x: rowX, y: paddingBottom + nameHeight + nameGap, width: rowWidth, height: iconSide)
        nameField.frame = NSRect(x: paddingX, y: paddingBottom, width: width - paddingX * 2, height: nameHeight)
        nameField.stringValue = targets[index].title

        iconHost.subviews.forEach { $0.removeFromSuperview() }
        for (offset, target) in targets.enumerated() {
            let originX = CGFloat(offset) * (iconSide + iconGap)
            if offset == index {
                let highlight = NSView(frame: NSRect(
                    x: originX - 4,
                    y: -4,
                    width: iconSide + 8,
                    height: iconSide + 8
                ))
                highlight.wantsLayer = true
                highlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
                highlight.layer?.cornerRadius = 10
                iconHost.addSubview(highlight)
            }
            let iconView = NSImageView(frame: NSRect(x: originX, y: 0, width: iconSide, height: iconSide))
            iconView.imageScaling = .scaleProportionallyUpOrDown
            let icon = target.app.icon ?? NSImage(named: NSImage.applicationIconName)
            icon?.size = NSSize(width: iconSide, height: iconSide)
            iconView.image = icon
            iconHost.addSubview(iconView)
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
