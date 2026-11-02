import AppKit
import ApplicationServices
import Carbon
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

/// Weak box so CGEvent tap callbacks no-op after the suppressor is released.
private final class MotionTapContext {
    weak var suppressor: SystemMotionSuppressor?
}

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
    private var mode: SystemMotionMode = .off

    private var swipeGesture = SwipeGestureState()

    private var session: Session?
    private var switcherBuildInFlight = false
    private var sessionIdle: DispatchWorkItem?
    private var mru: [pid_t] = []
    private var pendingActivation: SwitchTarget?
    private var activationFallback: DispatchWorkItem?
    /// True while our own activate(_:) is raising an app, so appActivated does not re-enter.
    private var isActivatingInternally = false

    /// Accessibility calls that hang on a beachballed app must not block the keyboard tap.
    private let axTimeoutSeconds: Float = 0.1
    /// Finger must travel at least this far before a released swipe commits a Space change.
    private let swipeCommitThreshold: Double = 0.08
    /// Cancel an open Command-Tab session after this much idle time.
    private let sessionIdleInterval: TimeInterval = 10

    private let tabKeyCode: Int64 = Int64(kVK_Tab)
    private let leftArrowKeyCode: Int64 = Int64(kVK_LeftArrow)
    private let rightArrowKeyCode: Int64 = Int64(kVK_RightArrow)

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

    func apply(_ newMode: SystemMotionMode) {
        let previous = mode
        mode = newMode

        if previous.commandTabEnabled, !newMode.commandTabEnabled {
            cancelSession()
        }

        if !newMode.wantsTaps {
            stop()
            return
        }

        if gestureTap != nil || keyTap != nil {
            // Taps already installed; mode flags update in place.
            return
        }
        startTaps()
    }

    private func startTaps() {
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
        log.info("System motion taps are on")
    }

    private func stop() {
        cancelSession()
        pendingActivation = nil
        activationFallback?.cancel()
        activationFallback = nil
        isActivatingInternally = false
        swipeGesture = SwipeGestureState()
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
            cancelSession()
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
        if mode.suppressDesktopMotion {
            _ = swipeGesture.expireIfStuck(now: Date())

            if let swipe = DockSwipeSwitcher.horizontalSwipe(in: event) {
                consume(swipe)
                return nil
            }
            if swipeGesture.swallowingSwipe, DockSwipeSwitcher.isGestureCompanion(event) {
                return nil
            }
        }
        return handleKeyboard(type: type, event: event)
    }

    /// Swallow the live gesture and only jump when the finger lifts past the commit threshold.
    /// That lets a reversed or aborted swipe cancel, matching Mission Control's habit.
    private func consume(_ swipe: DockSwipeSwitcher.HorizontalSwipe) {
        let sample = SwipeSample(
            progress: swipe.progress,
            direction: swipe.direction.map(swipeDirection(from:)),
            began: swipe.began,
            ended: swipe.ended
        )
        if let direction = swipeGesture.consume(
            sample,
            now: Date(),
            commitThreshold: swipeCommitThreshold,
            stuckInterval: 1.5
        ) {
            _ = spaceService.moveOneSpaceInstantly(direction: hopDirection(direction))
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

        if mode.suppressDesktopMotion, let direction = controlArrowDirection(type: type, event: event) {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                _ = spaceService.moveOneSpaceInstantly(direction: hopDirection(direction))
            }
            return nil
        }

        guard mode.commandTabEnabled else { return event }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)
        let extra = event.flags.contains(.maskAlternate) || event.flags.contains(.maskControl)

        guard command, !extra, keyCode == tabKeyCode else { return event }
        if type == .keyUp {
            return nil
        }
        guard type == .keyDown else { return event }

        // Swallow the opening keyDown before enumerating windows; build on the next turn.
        if switcherBuildInFlight || event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        switcherBuildInFlight = true
        let forward = !shift
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.switcherBuildInFlight = false }
            guard NSEvent.modifierFlags.contains(.command) else { return }

            let apps = self.orderedApps()
            guard let front = apps.first else { return }
            let targets = self.switchTargets(apps: apps)
            guard targets.count >= 2 else { return }
            let index = commandTabOpeningIndex(
                appIDs: targets.map { Int64($0.app.processIdentifier) },
                frontAppID: Int64(front.processIdentifier),
                forward: forward
            )
            self.session = Session(targets: targets, index: index)
            self.hud.show(targets: targets, selectedIndex: index)
            self.armSessionIdle()
        }
        return nil
    }

    /// While the switcher is open, keys go to Altitude — not the frontmost app.
    /// Tab / arrows move, Escape cancels, Q quits and H hides the highlighted app.
    private func handleSwitcherKey(type: CGEventType, event: CGEvent) -> CGEvent? {
        let action = CommandTabKeys.action(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            command: event.flags.contains(.maskCommand),
            shift: event.flags.contains(.maskShift),
            alternate: event.flags.contains(.maskAlternate),
            control: event.flags.contains(.maskControl),
            isKeyDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        switch action {
        case .move(let delta):
            moveSelection(by: delta)
        case .cancel:
            cancelSession()
        case .commit:
            commitSession()
        case .quit:
            quitHighlighted()
        case .hide:
            hideHighlighted()
        case .swallow:
            break
        }
        return nil
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
        armSessionIdle()
    }

    private func armSessionIdle() {
        sessionIdle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.cancelSession()
        }
        sessionIdle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionIdleInterval, execute: work)
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

    private func swipeDirection(from direction: DockSwipeSwitcher.Direction) -> SwipeDirection {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    private func hopDirection(_ direction: DockSwipeSwitcher.Direction) -> SpaceHopDirection {
        hopDirection(swipeDirection(from: direction))
    }

    private func hopDirection(_ direction: SwipeDirection) -> SpaceHopDirection {
        switch direction {
        case .left:
            return .previous
        case .right:
            return .next
        }
    }

    private func commitSession() {
        sessionIdle?.cancel()
        sessionIdle = nil
        guard let session else { return }
        self.session = nil
        hud.hide()
        guard session.targets.indices.contains(session.index), session.index != 0 else { return }
        let target = session.targets[session.index]
        let spaces = target.windowID.map { CGSPrivate.spaceIDs(forWindow: $0) } ?? []
        let instant = mode.commandTabInstantLanding
        switch spaceService.switchToPreferredSpace(among: spaces, instant: instant) {
        case .posted(let steps):
            // Let the swipe land before activation, or macOS starts its own slide.
            let delay: TimeInterval
            if instant {
                delay = 0.08 + 0.06 * Double(max(steps, 1))
            } else {
                delay = DockSwipeSwitcher.estimatedDuration(steps: steps, instant: false) + 0.08
            }
            armActivation(of: target, after: delay)
        case .alreadyThere, .otherDisplay, .unavailable:
            activate(target)
        }
    }

    private func cancelSession() {
        sessionIdle?.cancel()
        sessionIdle = nil
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
        // macOS 14+ cooperative activation requires `from` to be the real frontmost
        // app (still Rex/etc. — the HUD is nonactivating). `.current` (Altitude) made
        // same-Space picks no-op; cross-Space still worked via the Dock hop.
        isActivatingInternally = true
        focus(target)
        let donor = NSWorkspace.shared.frontmostApplication ?? .current
        _ = target.app.activate(from: donor, options: [])
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
            (element: element, title: element.axString(kAXTitleAttribute as String), size: element.axSize())
        }
        if let windowID = target.windowID, windowID != 0 {
            if let match = described.first(where: { $0.element.axWindowID() == windowID }) {
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
                    || WindowCatalog.isWeakTitle(item.title, appName: appName)
                    || WindowCatalog.isWeakTitle(target.title, appName: appName)
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

    /// Front app's windows as one block, then other apps in MRU order; empty apps trail.
    private func switchTargets(apps: [NSRunningApplication]) -> [SwitchTarget] {
        let byPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        let slots = commandTabRow(
            apps: apps.map { app in
                (appID: Int64(app.processIdentifier), windows: userWindows(for: app))
            }
        )
        return slots.compactMap { slot in
            guard let app = byPID[pid_t(slot.appID)] else { return nil }
            if let window = slot.window {
                return makeTarget(app: app, window: window)
            }
            return SwitchTarget(
                app: app,
                windowID: nil,
                title: app.localizedName ?? "Application",
                width: 0,
                height: 0
            )
        }
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

    /// Accessibility covers the current Space; the window-server list adds windows on other Spaces.
    private func userWindows(for app: NSRunningApplication) -> [ListedWindow] {
        let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ax = accessibilityWindows(for: app)
        let cg = WindowCatalog.dedupe(cgWindows(pid: app.processIdentifier, appName: appName), appName: appName)
        let isOnActiveSpace: ((CGWindowID) -> Bool)?
        if ax.isEmpty {
            isOnActiveSpace = nil
        } else {
            let activeSpaceID = CGSPrivate.activeSpaceID()
            isOnActiveSpace = { id in
                CGSPrivate.spaceIDs(forWindow: id).contains(activeSpaceID)
            }
        }
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: appName,
            isOnActiveSpace: isOnActiveSpace
        )
        return WindowCatalog.collapseRedundantWeakWindows(merged, appName: appName)
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
            let role = element.axString(kAXRoleAttribute as String)
            guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }
            let subrole = element.axString(kAXSubroleAttribute as String)
            if subrole == "AXUnknown" || subrole == "AXSystemDialog" { return nil }
            guard let size = element.axSize() else { return nil }
            guard size.width >= 160, size.height >= 100 else { return nil }
            let title = element.axString(kAXTitleAttribute as String)
            let id = element.axWindowID()
            return ListedWindow(
                id: id == 0 ? nil : id,
                title: title,
                width: size.width,
                height: size.height,
                main: element.axBool(kAXMainAttribute as String)
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
            if WindowCatalog.isHiddenHelper(
                width: width,
                height: height,
                title: title,
                onscreen: onscreen,
                appName: appName
            ) {
                return nil
            }
            // Prefs chrome some apps publish to CG without exposing it to Accessibility (Rex).
            if !appName.isEmpty, title == "\(appName) Settings" { return nil }
            // Tiny untitled / app-named surfaces are not user windows.
            if WindowCatalog.isWeakTitle(title, appName: appName), width < 480 || height < 320 { return nil }
            return (ListedWindow(id: windowID, title: title, width: width, height: height, main: onscreen), onscreen)
        }
        let hasOnscreen = candidates.contains(where: \.1)
        return candidates.compactMap { window, onscreen in
            if hasOnscreen, !onscreen, WindowCatalog.isWeakTitle(window.title, appName: appName) {
                return nil
            }
            return window
        }
    }

    private func orderedApps() -> [NSRunningApplication] {
        var ordered: [NSRunningApplication] = []
        var seen = Set<pid_t>()
        func consider(_ app: NSRunningApplication) {
            guard app.activationPolicy == .regular, !app.isTerminated else { return }
            // Include Altitude only while it is regular (Settings open). As an
            // accessory agent it fails the policy check above and stays out.
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

        // Keep MRU while taps are running. Hop only when desktop motion is suppressed.
        guard gestureTap != nil else { return }
        guard mode.suppressDesktopMotion else { return }
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
