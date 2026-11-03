import AppKit
import ApplicationServices
import Carbon
@preconcurrency import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "SystemMotion")

/// Decision state read by the tap callback. Mutated only on the tap thread.
private final class TapDecisionState: @unchecked Sendable {
    var mode: SystemMotionMode = .off
    var swipeGesture = SwipeGestureState()
    var sessionOpen = false
    var switcherBuildInFlight = false
}

/// Weak box so CGEvent tap callbacks no-op after the suppressor is released.
private final class MotionTapContext: @unchecked Sendable {
    weak var suppressor: SystemMotionSuppressor?
    weak var tapHost: EventTapHost?
    let decision = TapDecisionState()
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
@MainActor
final class SystemMotionSuppressor: NSObject {
    private let spaceService: SpaceService
    private let hud = AppSwitchHUD()
    private let tapHost = EventTapHost()
    private let focuser = WindowFocuser()
    private let tapContext = MotionTapContext()
    private var didLogTapFailure = false
    private var mode: SystemMotionMode = .off

    private var session: CommandTabSession<SwitchTarget>?
    private var sessionIdle: DispatchWorkItem?
    private var mru: [pid_t] = []
    private var pendingActivation: SwitchTarget?
    private var activationFallback: DispatchWorkItem?
    private var activationPoll: DispatchWorkItem?

    init(spaceService: SpaceService) {
        self.spaceService = spaceService
        super.init()
        tapContext.suppressor = self
        tapContext.tapHost = tapHost
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
        tapHost.tearDown()
    }

    func apply(_ newMode: SystemMotionMode) {
        let previous = mode
        mode = newMode
        publishDecision { $0.mode = newMode }

        if previous.commandTabEnabled, !newMode.commandTabEnabled {
            cancelSession()
        }

        let plan = MotionTapPlan(mode: newMode)
        if !plan.wantsAnyTap {
            stop()
            return
        }

        if tapHost.installedPlan != plan {
            tapHost.tearDown()
            startTaps(plan: plan)
        }
    }

    private func startTaps(plan: MotionTapPlan) {
        guard AXIsProcessTrusted() else {
            logTapFailure("Accessibility is required to disable trackpad, Control-arrow, and Command-Tab motion")
            return
        }

        let userInfo = Unmanaged.passUnretained(tapContext).toOpaque()
        let result = tapHost.install(plan: plan, callback: Self.callback, userInfo: userInfo)
        guard result.ok else {
            logTapFailure("Could not create the event tap that disables system motion")
            return
        }
        if result.hidFailed {
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
        activationPoll?.cancel()
        activationPoll = nil
        focuser.reset()
        publishDecision { $0.swipeGesture = SwipeGestureState() }
        tapHost.tearDown()
    }

    /// Mirror callback decision fields onto the tap thread.
    private func publishDecision(_ update: @escaping (TapDecisionState) -> Void) {
        let decision = tapContext.decision
        tapHost.asyncOnTapThread {
            update(decision)
        }
    }

    // MARK: - Tap

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<MotionTapContext>.fromOpaque(userInfo).takeUnretainedValue()
        guard context.suppressor != nil else {
            return Unmanaged.passUnretained(event)
        }
        if let forwarded = context.handleOnTapThread(type: type, event: event) {
            return Unmanaged.passUnretained(forwarded)
        }
        return nil
    }
}

extension MotionTapContext {
    private static let tabKeyCode: Int64 = Int64(kVK_Tab)
    private static let leftArrowKeyCode: Int64 = Int64(kVK_LeftArrow)
    private static let rightArrowKeyCode: Int64 = Int64(kVK_RightArrow)
    private static let swipeCommitThreshold: Double = Timing.swipeCommitThreshold

    /// Decide forward vs drop on the tap thread. Schedule main-actor effects with async only.
    fileprivate func handleOnTapThread(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapHost?.reenable()
            DispatchQueue.main.async { [weak suppressor] in
                suppressor?.cancelSessionFromTap()
            }
            log.error("Event tap was disabled (\(type.rawValue, privacy: .public)); re-enabled")
            return event
        }

        if DockSwipeSwitcher.isOwnEvent(event) {
            return event
        }
        if decision.mode.suppressDesktopMotion {
            _ = decision.swipeGesture.expireIfStuck(now: Date())

            if let swipe = DockSwipeSwitcher.horizontalSwipe(in: event) {
                consumeSwipe(swipe)
                return nil
            }
            if decision.swipeGesture.swallowingSwipe, DockSwipeSwitcher.isGestureCompanion(event) {
                return nil
            }
        }
        return handleKeyboard(type: type, event: event)
    }

    private func consumeSwipe(_ swipe: DockSwipeSwitcher.HorizontalSwipe) {
        let sample = SwipeSample(
            progress: swipe.progress,
            direction: swipe.direction.map(Self.swipeDirection(from:)),
            began: swipe.began,
            ended: swipe.ended
        )
        if let direction = decision.swipeGesture.consume(
            sample,
            now: Date(),
            commitThreshold: Self.swipeCommitThreshold,
            stuckInterval: Timing.swipeStuckInterval
        ) {
            let hop = Self.hopDirection(direction)
            DispatchQueue.main.async { [weak suppressor] in
                suppressor?.hopOneSpaceFromTap(direction: hop)
            }
        }
    }

    private func handleKeyboard(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .flagsChanged {
            if decision.sessionOpen, !event.flags.contains(.maskCommand) {
                DispatchQueue.main.async { [weak suppressor] in
                    suppressor?.commitSessionFromTap()
                }
            }
            return event
        }

        if decision.sessionOpen {
            return handleSwitcherKey(type: type, event: event)
        }

        if decision.mode.suppressDesktopMotion, let direction = controlArrowDirection(type: type, event: event) {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let hop = Self.hopDirection(direction)
                DispatchQueue.main.async { [weak suppressor] in
                    suppressor?.hopOneSpaceFromTap(direction: hop)
                }
            }
            return nil
        }

        guard decision.mode.commandTabEnabled else { return event }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let command = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)
        let extra = event.flags.contains(.maskAlternate) || event.flags.contains(.maskControl)

        guard command, !extra, keyCode == Self.tabKeyCode else { return event }
        if type == .keyUp {
            return nil
        }
        guard type == .keyDown else { return event }

        // Swallow the opening keyDown before enumerating windows; build on the next turn.
        if decision.switcherBuildInFlight || event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        decision.switcherBuildInFlight = true
        let forward = !shift
        DispatchQueue.main.async { [weak suppressor] in
            suppressor?.openCommandTabFromTap(forward: forward)
        }
        return nil
    }

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
        DispatchQueue.main.async { [weak suppressor] in
            suppressor?.performSwitcherActionFromTap(action)
        }
        return nil
    }

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
        case Self.leftArrowKeyCode:
            return .left
        case Self.rightArrowKeyCode:
            return .right
        default:
            return nil
        }
    }

    private static func swipeDirection(from direction: DockSwipeSwitcher.Direction) -> SwipeDirection {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    private static func hopDirection(_ direction: DockSwipeSwitcher.Direction) -> SpaceHopDirection {
        hopDirection(swipeDirection(from: direction))
    }

    private static func hopDirection(_ direction: SwipeDirection) -> SpaceHopDirection {
        switch direction {
        case .left:
            return .previous
        case .right:
            return .next
        }
    }
}

extension SystemMotionSuppressor {
    // MARK: - Effects scheduled from the tap thread

    fileprivate func hopOneSpaceFromTap(direction: SpaceHopDirection) {
        _ = spaceService.moveOneSpaceInstantly(direction: direction)
    }

    fileprivate func cancelSessionFromTap() {
        cancelSession()
    }

    fileprivate func commitSessionFromTap() {
        commitSession()
    }

    fileprivate func openCommandTabFromTap(forward: Bool) {
        defer {
            publishDecision { $0.switcherBuildInFlight = false }
        }
        guard NSEvent.modifierFlags.contains(.command) else { return }

        let apps = orderedApps()
        guard let front = apps.first else { return }
        let targets = switchTargets(apps: apps)
        let index = commandTabOpeningIndex(
            appIDs: targets.map { Int64($0.app.processIdentifier) },
            frontAppID: Int64(front.processIdentifier),
            forward: forward
        )
        let now = Date()
        guard let opened = CommandTabSession.open(targets: targets, index: index, now: now) else {
            return
        }
        session = opened
        publishDecision { $0.sessionOpen = true }
        hud.show(targets: targets, selectedIndex: index)
        armSessionIdle()
    }

    fileprivate func performSwitcherActionFromTap(_ action: CommandTabSwitcherAction) {
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
    }

    private func moveSelection(by delta: Int) {
        guard var current = session else { return }
        let now = Date()
        if current.move(by: delta, now: now) {
            cancelSession()
            return
        }
        session = current
        hud.show(targets: current.targets, selectedIndex: current.index)
        armSessionIdle()
    }

    private func armSessionIdle() {
        sessionIdle?.cancel()
        guard let deadline = session?.idleDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.cancelSession()
        }
        sessionIdle = work
        let delay = max(deadline.timeIntervalSinceNow, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func commitSession() {
        sessionIdle?.cancel()
        sessionIdle = nil
        guard let session else { return }
        self.session = nil
        publishDecision { $0.sessionOpen = false }
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
                delay = Timing.instantLandingDelay(steps: steps)
            } else {
                delay = DockSwipeSwitcher.estimatedDuration(steps: steps, instant: false) + 0.08
            }
            armActivation(of: target, after: delay)
        case .alreadyThere, .otherDisplay, .unavailable:
            focuser.activate(target)
        }
    }

    private func cancelSession() {
        sessionIdle?.cancel()
        sessionIdle = nil
        session = nil
        publishDecision { $0.sessionOpen = false }
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
        activationPoll?.cancel()

        // Poll active Space so we raise the target as soon as the hop lands — ideally
        // before the destination Space's previous front app paints (the Rex flash).
        let destinations = Set(target.windowID.map { CGSPrivate.spaceIDs(forWindow: $0) } ?? [])
        let startSpace = CGSPrivate.activeSpaceID()
        let giveUp = Date().addingTimeInterval(delay)
        func schedulePoll(after interval: TimeInterval) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let pending = self.pendingActivation, pending.sameInstance(as: target) else { return }
                let active = CGSPrivate.activeSpaceID()
                if !destinations.isEmpty, destinations.contains(active), active != startSpace {
                    self.promotePendingActivation(matching: target)
                    return
                }
                if Date() >= giveUp {
                    self.promotePendingActivation(matching: target)
                    return
                }
                schedulePoll(after: Timing.activationPollInterval)
            }
            self.activationPoll = work
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        }
        schedulePoll(after: 0)

        // Absolute fallback if Space never reports (same as prior landing delay).
        let fallback = DispatchWorkItem { [weak self] in
            self?.promotePendingActivation(matching: target)
        }
        activationFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fallback)
    }

    /// Raise the armed Command-Tab / external-hop target once the hop has landed (or timed out).
    private func promotePendingActivation(matching target: SwitchTarget? = nil) {
        guard let pending = pendingActivation else { return }
        if let target, !pending.sameInstance(as: target) { return }
        pendingActivation = nil
        activationFallback?.cancel()
        activationFallback = nil
        activationPoll?.cancel()
        activationPoll = nil
        focuser.activate(pending)
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
            let delay = Timing.instantLandingDelay(steps: steps)
            armActivation(of: target, after: delay)
        case .alreadyThere:
            focuser.activate(target)
        case .otherDisplay, .unavailable:
            break
        }
    }

    /// Front app's windows as one block, then other apps in MRU order; empty apps trail.
    private func switchTargets(apps: [NSRunningApplication]) -> [SwitchTarget] {
        let byPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        let windowsByPID = windowListGroupedByPID()
        let activeSpaceID = CGSPrivate.activeSpaceID()
        let slots = commandTabRow(
            apps: apps.map { app in
                let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rows = windowsByPID[app.processIdentifier] ?? []
                return (
                    appID: Int64(app.processIdentifier),
                    windows: userWindows(for: app, cgRows: rows, activeSpaceID: activeSpaceID, appName: appName)
                )
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

    /// One window-server copy, grouped by owner PID for the Command-Tab build.
    private func windowListGroupedByPID() -> [pid_t: [[String: Any]]] {
        guard let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var grouped: [pid_t: [[String: Any]]] = [:]
        for dict in info {
            guard let owner = dict[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(owner.int32Value)
            grouped[pid, default: []].append(dict)
        }
        return grouped
    }

    /// Accessibility covers the current Space; the window-server list adds windows on other Spaces.
    private func userWindows(for app: NSRunningApplication) -> [ListedWindow] {
        let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return userWindows(for: app, cgRows: [], activeSpaceID: CGSPrivate.activeSpaceID(), appName: appName)
        }
        let pid = app.processIdentifier
        let rows = info.filter { dict in
            guard let owner = dict[kCGWindowOwnerPID as String] as? NSNumber else { return false }
            return owner.int32Value == pid
        }
        return userWindows(for: app, cgRows: rows, activeSpaceID: CGSPrivate.activeSpaceID(), appName: appName)
    }

    private func userWindows(
        for app: NSRunningApplication,
        cgRows: [[String: Any]],
        activeSpaceID: CGSSpaceID,
        appName: String
    ) -> [ListedWindow] {
        let ax = accessibilityWindows(for: app)
        let cg = WindowCatalog.dedupe(cgWindows(appName: appName, rows: cgRows), appName: appName)
        let isOnActiveSpace: ((CGWindowID) -> Bool)?
        if ax.isEmpty {
            isOnActiveSpace = nil
        } else {
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
        let axApp = focuser.axApplication(pid: app.processIdentifier)
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

    /// Window-server list slice for one app. Includes off-Space windows and drops Electron helpers.
    private func cgWindows(appName: String, rows: [[String: Any]]) -> [ListedWindow] {
        var seen = Set<CGWindowID>()
        let candidates: [(ListedWindow, Bool)] = rows.compactMap { dict in
            let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { return nil }
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

        if focuser.consumeInternalActivation(for: app.processIdentifier) {
            return
        }

        // Instant hop landed: the destination Space brought its previous front app
        // forward. Promote the pending target immediately so that app does not flash.
        if let pending = pendingActivation,
           app.processIdentifier != pending.app.processIdentifier
        {
            promotePendingActivation()
            return
        }

        // Keep MRU while taps are running. Hop only when desktop motion is suppressed.
        guard tapHost.hasAnyTap else { return }
        guard mode.suppressDesktopMotion else { return }
        if session != nil || focuser.isActivatingInternally || pendingActivation != nil { return }
        hopForExternalActivation(of: app)
    }

    private func logTapFailure(_ message: StaticString) {
        guard !didLogTapFailure else { return }
        didLogTapFailure = true
        log.error("\(message, privacy: .public)")
    }
}
