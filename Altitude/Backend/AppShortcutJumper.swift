import AppKit
import ApplicationServices
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "AppShortcuts")

/// Instant Space hop + focus for App Shortcuts hotkeys.
@MainActor
final class AppShortcutJumper {
    private let spaceService: SpaceService
    private let focuser: WindowFocuser

    private var pendingActivation: SwitchTarget?
    private var activationFallback: DispatchWorkItem?
    private var activationPoll: DispatchWorkItem?
    private var launchPoll: DispatchWorkItem?

    init(spaceService: SpaceService, focuser: WindowFocuser) {
        self.spaceService = spaceService
        self.focuser = focuser
    }

    func jump(toBundleID bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let app = runningApp(bundleID: trimmed) {
            if app.isActive {
                return
            }
            hopAndActivate(app)
            return
        }

        launchThenFocus(bundleID: trimmed)
    }

    // MARK: - Running

    private func hopAndActivate(_ app: NSRunningApplication) {
        guard let target = preferredTarget(for: app) else {
            // No window to locate — activate may let macOS slide; still best-effort focus.
            log.info("No window for \(app.bundleIdentifier ?? "?", privacy: .public); activating without hop")
            focuser.activate(SwitchTarget(
                app: app,
                windowID: nil,
                title: app.localizedName ?? "Application",
                width: 0,
                height: 0
            ))
            return
        }

        let spaces = target.windowID.map { CGSPrivate.spaceIDs(forWindow: $0) } ?? []
        // Empty candidates make switchInstantly report `.alreadyThere`, and a bare
        // activate() then triggers the Mission Control slide. Refuse that path.
        guard !spaces.isEmpty else {
            log.error("Window \(target.windowID ?? 0) has no Space IDs; refusing activate-driven slide")
            NSSound.beep()
            return
        }

        switch spaceService.switchInstantly(toPreferredSpaceAmong: spaces) {
        case .posted(let steps):
            let delay = Timing.instantLandingDelay(steps: steps)
            armActivation(of: target, after: delay)
        case .alreadyThere:
            focuser.activate(target)
        case .otherDisplay:
            // No managed strip owns this Space — activate without a hop (may slide).
            focuser.activate(target)
        case .unavailable:
            focuser.activate(target)
        }
    }

    /// Main window if Accessibility marked one; otherwise the first listed (AX+CG merge).
    private func preferredTarget(for app: NSRunningApplication) -> SwitchTarget? {
        let windows = userWindows(for: app)
        // Prefer a window that has Space IDs so we can hop instead of sliding.
        let withSpaces = windows.filter { window in
            guard let id = window.id else { return false }
            return !CGSPrivate.spaceIDs(forWindow: id).isEmpty
        }
        let preferred = withSpaces.first(where: \.main)
            ?? withSpaces.first
            ?? windows.first(where: \.main)
            ?? windows.first
        guard let preferred else { return nil }
        let title = preferred.title.isEmpty ? (app.localizedName ?? "Application") : preferred.title
        return SwitchTarget(
            app: app,
            windowID: preferred.id,
            title: title,
            width: preferred.width,
            height: preferred.height
        )
    }

    /// Same AX+CG merge idea as SystemMotionSuppressor: AX for the current Space,
    /// CG for off-Space windows so Space IDs resolve for instant hops.
    private func userWindows(for app: NSRunningApplication) -> [ListedWindow] {
        let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activeSpaceID = CGSPrivate.activeSpaceID()
        let cgRows: [[String: Any]]
        if let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let pid = app.processIdentifier
            cgRows = info.filter { dict in
                guard let owner = dict[kCGWindowOwnerPID as String] as? NSNumber else { return false }
                return owner.int32Value == pid
            }
        } else {
            cgRows = []
        }

        let ax = accessibilityWindows(for: app)
        let cg = WindowCatalog.dedupe(cgWindows(appName: appName, rows: cgRows), appName: appName)
        let isOnActiveSpace: ((CGWindowID) -> Bool)? = ax.isEmpty ? nil : { id in
            CGSPrivate.spaceIDs(forWindow: id).contains(activeSpaceID)
        }
        let merged = WindowCatalog.mergeWindows(
            ax: ax,
            cg: cg,
            appName: appName,
            isOnActiveSpace: isOnActiveSpace
        )
        // Same post-merge twin collapse as Command-Tab (Mail CG/AX duplicates).
        let twinsCollapsed = WindowCatalog.dedupe(merged, appName: appName)
        return WindowCatalog.collapseRedundantWeakWindows(twinsCollapsed, appName: appName)
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
        let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return windows.compactMap { element -> ListedWindow? in
            let role = element.axString(kAXRoleAttribute as String)
            guard role.isEmpty || role == (kAXWindowRole as String) else { return nil }
            let title = element.axString(kAXTitleAttribute as String)
            let subrole = element.axString(kAXSubroleAttribute as String)
            guard WindowCatalog.acceptsSwitchSubrole(subrole, title: title, appName: appName) else { return nil }
            guard let size = element.axSize() else { return nil }
            guard size.width >= 160, size.height >= 100 else { return nil }
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
            if !appName.isEmpty, title == "\(appName) Settings" { return nil }
            if WindowCatalog.isWeakTitle(title, appName: appName), width < 480 || height < 320 {
                return nil
            }
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

    // MARK: - Launch

    private func launchThenFocus(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("No application for bundle ID \(bundleID, privacy: .public)")
            NSSound.beep()
            return
        }
        launchPoll?.cancel()
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    log.error("Launch failed: \(error.localizedDescription, privacy: .public)")
                    NSSound.beep()
                    return
                }
                if let app, !app.isTerminated {
                    self.hopAndActivate(app)
                    return
                }
                self.pollForLaunch(bundleID: bundleID)
            }
        }
    }

    private func pollForLaunch(bundleID: String, attemptsRemaining: Int = 40) {
        launchPoll?.cancel()
        if let app = runningApp(bundleID: bundleID) {
            hopAndActivate(app)
            return
        }
        guard attemptsRemaining > 0 else {
            log.error("Timed out waiting for \(bundleID, privacy: .public) to launch")
            NSSound.beep()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pollForLaunch(bundleID: bundleID, attemptsRemaining: attemptsRemaining - 1)
        }
        launchPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && $0.activationPolicy == .regular && !$0.isTerminated
        }
    }

    // MARK: - Landing (mirrors SystemMotionSuppressor)

    private func armActivation(of target: SwitchTarget, after delay: TimeInterval) {
        pendingActivation = target
        activationFallback?.cancel()
        activationPoll?.cancel()

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

        let fallback = DispatchWorkItem { [weak self] in
            self?.promotePendingActivation(matching: target)
        }
        activationFallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fallback)
    }

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
}
