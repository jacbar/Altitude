import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os.log

/// One Command-Tab entry. An app with two windows produces two of these.
struct SwitchTarget {
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

/// Which system-motion behaviors the event taps should drive.
struct SystemMotionMode: Equatable, Sendable {
    /// Swallow trackpad Space swipes, Control-Left/Right, and hop on external app activation.
    var suppressDesktopMotion: Bool
    /// Replace the system Command-Tab switcher with Altitude's window row.
    var commandTabEnabled: Bool
    /// Skip the slide when landing on the highlighted Command-Tab window.
    var commandTabInstantLanding: Bool

    var wantsTaps: Bool { suppressDesktopMotion || commandTabEnabled }

    static let off = SystemMotionMode(
        suppressDesktopMotion: false,
        commandTabEnabled: false,
        commandTabInstantLanding: false
    )
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
    private let spaceService: SpaceService
    private let hud = AppSwitchHUD()
    private let taps = EventTapHost()
    private var didLogTapFailure = false
    private var mode: SystemMotionMode = .off

    private var swipeTracker = SwipeGestureTracker()

    private var session: CommandTabSession<SwitchTarget>?
    private var sessionIdleDeadline = Date.distantPast
    private var mru: [pid_t] = []
    private var pendingActivation: SwitchTarget?
    private var activationFallback: DispatchWorkItem?
    /// True while our own activate(_:) is raising an app, so appActivated does not re-enter.
    private var isActivatingInternally = false
    private var activatingPID: pid_t?
    private var activatingClearWork: DispatchWorkItem?

    /// Accessibility calls that hang on a beachballed app must not block the keyboard tap.
    private let axTimeoutSeconds: Float = 0.1
    /// Finger must travel at least this far before a released swipe commits a Space change.
    private let swipeCommitThreshold: Double = 0.08
    private let sessionIdleInterval: TimeInterval = 10

    init(spaceService: SpaceService) {
        self.spaceService = spaceService
        super.init()
        taps.handler = { [weak self] type, event in
            guard let self else { return event }
            return self.handle(type: type, event: event)
        }
        taps.onTapDisabled = { [weak self] in
            self?.cancelSession()
        }
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
        taps.handler = nil
        taps.onTapDisabled = nil
        taps.stop()
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

        guard AXIsProcessTrusted() else {
            logTapFailure("Accessibility is required to disable trackpad, Control-arrow, and Command-Tab motion")
            return
        }

        taps.start(mode: newMode)
        if taps.isRunning {
            didLogTapFailure = false
            log.info("System motion taps are on")
        } else {
            logTapFailure("Could not create the event tap that disables system motion")
        }
    }

    private func stop() {
        cancelSession()
        pendingActivation = nil
        activationFallback?.cancel()
        activationFallback = nil
        clearActivatingFlag()
        swipeTracker = SwipeGestureTracker()
        taps.stop()
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if session != nil, Date() > sessionIdleDeadline {
            cancelSession()
            return event
        }

        if DockSwipeSwitcher.isOwnEvent(event) {
            return event
        }
        if mode.suppressDesktopMotion {
            let now = Date()
            swipeTracker.clearIfExpired(now: now)

            if let swipe = DockSwipeSwitcher.horizontalSwipe(in: event) {
                if let hop = swipeTracker.consume(swipe, now: now, commitThreshold: swipeCommitThreshold) {
                    _ = spaceService.moveOneSpaceInstantly(direction: hop)
                }
                return nil
            }
            if swipeTracker.isSwallowing, DockSwipeSwitcher.isGestureCompanion(event) {
                return nil
            }
        }
        return handleKeyboard(type: type, event: event)
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

        guard command, !extra, keyCode == Int64(kVK_Tab) else { return event }
        if type == .keyUp {
            return nil
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }
        guard type == .keyDown else { return event }

        // Build the row after the tap returns so Accessibility / window-list work
        // never runs inside the callback.
        let forward = !shift
        DispatchQueue.main.async { [weak self] in
            self?.openSession(forward: forward)
        }
        // Mark idle so a stuck open cannot swallow forever if Command never returns.
        refreshSessionIdleDeadline()
        return nil
    }

    /// While the switcher is open, keys go to Altitude — not the frontmost app.
    /// Tab / arrows move, Escape cancels, Q quits and H hides the highlighted app.
    private func handleSwitcherKey(type: CGEventType, event: CGEvent) -> CGEvent? {
        refreshSessionIdleDeadline()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let action = commandTabKeyAction(keyCode: keyCode, flags: event.flags)

        switch action {
        case .move(let step):
            if type == .keyDown, !isRepeat {
                moveSelection(by: step)
            }
            return nil
        case .cancel:
            if type == .keyDown, !isRepeat {
                cancelSession()
            }
            return nil
        case .commit:
            if type == .keyDown || type == .keyUp {
                commitSession()
            }
            return nil
        case .quit:
            if type == .keyDown, !isRepeat {
                quitHighlighted()
            }
            return nil
        case .hide:
            if type == .keyDown, !isRepeat {
                hideHighlighted()
            }
            return nil
        case .drop:
            return nil
        }
    }

    private func openSession(forward: Bool) {
        guard mode.commandTabEnabled, session == nil else { return }
        // Command may have been released before this async work ran.
        guard NSEvent.modifierFlags.contains(.command) else { return }
        let apps = orderedApps()
        guard let front = apps.first else { return }
        let targets = switchTargets(apps: apps)
        guard targets.count >= 2 else { return }
        let index = commandTabOpeningIndex(
            appIDs: targets.map { Int64($0.app.processIdentifier) },
            frontAppID: Int64(front.processIdentifier),
            forward: forward
        )
        session = CommandTabSession(targets: targets, index: index)
        refreshSessionIdleDeadline()
        hud.show(targets: targets, selectedIndex: index)
    }

    private func refreshSessionIdleDeadline() {
        sessionIdleDeadline = Date().addingTimeInterval(sessionIdleInterval)
    }

    private func moveSelection(by delta: Int) {
        guard var current = session else { return }
        let count = current.targets.count
        guard count >= 2, delta != 0 else {
            if count < 2 { cancelSession() }
            return
        }
        current.move(by: delta)
        session = current
        refreshSessionIdleDeadline()
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
        case Int64(kVK_LeftArrow):
            return .left
        case Int64(kVK_RightArrow):
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
        activatingPID = target.app.processIdentifier
        activatingClearWork?.cancel()
        let clear = DispatchWorkItem { [weak self] in
            guard let self, self.activatingPID == target.app.processIdentifier else { return }
            self.clearActivatingFlag()
        }
        activatingClearWork = clear
        // Fallback if didActivateApplicationNotification never arrives for this PID.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: clear)

        focus(target)
        _ = target.app.activate(from: .current, options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.focus(target)
        }
    }

    private func clearActivatingFlag() {
        isActivatingInternally = false
        activatingPID = nil
        activatingClearWork?.cancel()
        activatingClearWork = nil
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
            (element: element, title: AXRead.string(element, kAXTitleAttribute as String), size: AXRead.size(element))
        }
        if let windowID = target.windowID, windowID != 0 {
            if let match = described.first(where: { AXRead.windowID($0.element) == windowID }) {
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
        let activeSpace = ax.isEmpty ? nil : CGSPrivate.activeSpaceID()
        return WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: appName,
            activeSpaceID: activeSpace,
            spaceIDsForWindow: { CGSPrivate.spaceIDs(forWindow: $0) }
        )
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
            let role = AXRead.string(element, kAXRoleAttribute as String)
            guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }
            let subrole = AXRead.string(element, kAXSubroleAttribute as String)
            if subrole == "AXUnknown" || subrole == "AXSystemDialog" { return nil }
            guard let size = AXRead.size(element) else { return nil }
            guard size.width >= 160, size.height >= 100 else { return nil }
            let title = AXRead.string(element, kAXTitleAttribute as String)
            let id = AXRead.windowID(element)
            return ListedWindow(
                id: id == 0 ? nil : id,
                title: title,
                width: size.width,
                height: size.height,
                main: AXRead.bool(element, kAXMainAttribute as String)
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
            if hasOnscreen, !onscreen, WindowCatalog.isWeakTitle(window.title, appName: appName) { return nil }
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

        if isActivatingInternally, activatingPID == app.processIdentifier {
            clearActivatingFlag()
        }

        // Keep MRU while taps are running. Hop only when desktop motion is suppressed.
        guard taps.isRunning else { return }
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
