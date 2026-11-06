import AppKit
import ApplicationServices
import Foundation

/// Raises a SwitchTarget's window and tracks internal activation so external hops do not re-enter.
@MainActor
final class WindowFocuser {
    /// Accessibility calls that hang on a beachballed app must not block the keyboard tap.
    private let axTimeoutSeconds: Float = 0.1

    private(set) var isActivatingInternally = false
    private(set) var activatingPID: pid_t?
    private var activationGuard: DispatchWorkItem?
    /// App Shortcut / Command-Tab hops arm this before `activate` so external activation
    /// does not race into `hopForExternalActivation` while landing is still pending.
    private var pendingHopCount = 0
    /// Bumped on each `activate` / `reset` so in-flight focus retries no-op.
    private var focusGeneration = 0

    /// True while an activate is in progress or a Space-hop landing is armed.
    var isActivationInFlight: Bool {
        isActivatingInternally || pendingHopCount > 0
    }

    /// Call when arming a post-hop activation; pair with `endPendingHop`.
    func beginPendingHop() {
        pendingHopCount += 1
    }

    /// Call when clearing a post-hop activation (promote, cancel, or stop).
    func endPendingHop() {
        if pendingHopCount > 0 {
            pendingHopCount -= 1
        }
    }

    /// Raise first, then again after activate(). Activation focuses the app's main
    /// window on its own, which is why an Outlook message was opening the inbox.
    /// macOS 14+ cooperative activation requires `from` to be the real frontmost
    /// app (still Rex/etc. — the HUD is nonactivating). `.current` (Altitude) made
    /// same-Space picks no-op; cross-Space still worked via the Dock hop.
    func activate(_ target: SwitchTarget) {
        let pid = target.app.processIdentifier
        isActivatingInternally = true
        activatingPID = pid
        activationGuard?.cancel()
        focusGeneration += 1
        let generation = focusGeneration
        let guardWork = DispatchWorkItem { [weak self] in
            guard let self, self.activatingPID == pid else { return }
            self.isActivatingInternally = false
            self.activatingPID = nil
            self.activationGuard = nil
        }
        activationGuard = guardWork
        focus(target)
        let donor = NSWorkspace.shared.frontmostApplication ?? .current
        _ = target.app.activate(from: donor, options: [])
        // Next runloop raise — activation often steals focus to AX main immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusGeneration == generation else { return }
            self.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focusRetryShort) { [weak self] in
            guard let self, self.focusGeneration == generation else { return }
            self.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focusRetryMid) { [weak self] in
            guard let self, self.focusGeneration == generation else { return }
            self.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focusRetryLong) { [weak self] in
            guard let self, self.focusGeneration == generation else { return }
            self.focus(target)
        }
        // Slightly after the long retry so a late main-window steal still loses.
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.focusRetryLong + 0.08) { [weak self] in
            guard let self, self.focusGeneration == generation else { return }
            self.focus(target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.activationGuard, execute: guardWork)
    }

    /// Clears the internal-activation guard when our own raise lands.
    @discardableResult
    func consumeInternalActivation(for pid: pid_t) -> Bool {
        guard pid == activatingPID else { return false }
        activationGuard?.cancel()
        activationGuard = nil
        isActivatingInternally = false
        activatingPID = nil
        return true
    }

    func reset() {
        activationGuard?.cancel()
        activationGuard = nil
        activatingPID = nil
        isActivatingInternally = false
        pendingHopCount = 0
        focusGeneration += 1
    }

    /// Raise the selected window, matching the accessibility window by id, then by title and size.
    func focus(_ target: SwitchTarget) {
        guard AXIsProcessTrusted(), let window = axWindow(matching: target) else { return }
        let appElement = axApplication(pid: target.app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func axWindow(matching target: SwitchTarget) -> AXUIElement? {
        let appElement = axApplication(pid: target.app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return nil
        }
        let described = windows.map { element in
            (
                element: element,
                title: element.axString(kAXTitleAttribute as String),
                size: element.axSize(),
                main: element.axBool(kAXMainAttribute as String),
                windowID: element.axWindowID()
            )
        }
        if let windowID = target.windowID, windowID != 0 {
            if let match = described.first(where: { $0.windowID == windowID }) {
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
        guard !titled.isEmpty else { return nil }
        if titled.count == 1 { return titled[0].element }

        // Ambiguous weak titles: if the target is not the app's current main, prefer non-main.
        let axMain = described.first(where: \.main)
        let targetIsMain: Bool = {
            if let windowID = target.windowID, windowID != 0 {
                // Id present but did not bind above — only "main" when it equals AX main's id.
                guard let mainID = axMain?.windowID, mainID != 0 else { return false }
                return windowID == mainID
            }
            guard let main = axMain, let size = main.size else { return false }
            let sizeMatches = abs(size.width - target.width) < 4 && abs(size.height - target.height) < 4
            guard sizeMatches else { return false }
            // Without an id, only a strong title match identifies the main window.
            return !WindowCatalog.isWeakTitle(target.title, appName: appName)
                && target.title == main.title
        }()
        if !targetIsMain, let nonMain = titled.first(where: { !$0.main }) {
            return nonMain.element
        }
        if let mainMatch = titled.first(where: \.main) {
            return mainMatch.element
        }
        return titled.first?.element
    }

    func axApplication(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axTimeoutSeconds)
        return element
    }
}
