import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "MenuBar")

@MainActor
final class MenuBarController: NSObject {
    private static let didPromptForAccessibilityKey = "didPromptForAccessibility"

    private let statusItem: NSStatusItem
    private let spaceService: SpaceService
    private let focusResolver: FocusedWindowResolver
    private var hotkeys: HotkeyRegistrar!
    private var config: AppConfig
    private var pollTimer: Timer?
    private var lastSnapshot = SpaceSnapshot.empty
    private var motionSuppressor: SystemMotionSuppressor?

    init(spaceService: SpaceService, focusResolver: FocusedWindowResolver) {
        self.spaceService = spaceService
        self.focusResolver = focusResolver
        self.config = ConfigStore.load()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        self.hotkeys = HotkeyRegistrar { [weak self] action in
            Task { @MainActor in
                self?.handle(action: action)
            }
        }

        // Avoid autosave-name hide bugs on Tahoe; keep the item always visible.
        statusItem.autosaveName = nil
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.title = ""
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "Altitude"
            button.appearsDisabled = false
        }

        spaceService.instantSwitching = config.disableAnimations
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        startPolling()
        observeWorkspace()
        log.info("Status item created (visible=\(self.statusItem.isVisible, privacy: .public))")
    }

    func bootstrapAccessibility() {
        let trusted = focusResolver.isAccessibilityTrusted
        log.info("Accessibility trusted=\(trusted, privacy: .public)")
        // Register this exact binary in the Accessibility list once. Hotkeys must
        // not open System Settings — that fired on every Option+digit. Later
        // launches rely on the menu item instead of re-prompting.
        let defaults = UserDefaults.standard
        if !trusted, !defaults.bool(forKey: Self.didPromptForAccessibilityKey) {
            _ = focusResolver.promptForAccessibilityIfNeeded()
            defaults.set(true, forKey: Self.didPromptForAccessibilityKey)
        }
        buildMenu()
        refreshIndicator()
        updateSystemMotions()
    }

    // MARK: - Actions

    private func handle(action: HotkeyAction) {
        do {
            switch action {
            case .switchTo(let index):
                try spaceService.switchTo(index: index)
            case .moveTo(let index):
                try spaceService.moveFocusedWindow(to: index)
            }
            // Dock-swipe transitions settle after the gesture frames are posted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refreshSpacesAndHotkeys()
            }
        } catch SpaceServiceError.accessibilityDenied {
            // Don't open System Settings here — that fired on every Option+digit
            // while trust was missing. The menu item is the explicit path.
            log.error("Accessibility required for space switching")
            NSSound.beep()
        } catch {
            log.error("Hotkey action failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    @objc private func refreshFromMenu() {
        config = ConfigStore.load()
        spaceService.instantSwitching = config.disableAnimations
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        buildMenu()
    }

    @objc private func openConfig() {
        ConfigStore.ensureExampleIfMissing()
        NSWorkspace.shared.open(ConfigStore.configFileURL)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        _ = focusResolver.promptForAccessibilityIfNeeded()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func switchToSpaceFromMenu(_ sender: NSMenuItem) {
        handle(action: .switchTo(sender.tag))
    }

    // MARK: - Menu / indicator

    private func buildMenu() {
        let menu = NSMenu()
        let axOK = focusResolver.isAccessibilityTrusted

        if !axOK {
            let warn = NSMenuItem(
                title: "Accessibility permission required",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        if lastSnapshot.spaces.isEmpty {
            menu.addItem(NSMenuItem(title: "No Spaces detected", action: nil, keyEquivalent: ""))
        } else {
            for space in lastSnapshot.spaces {
                let title = space.isCurrent ? "Desktop \(space.index) ✓" : "Desktop \(space.index)"
                let item = NSMenuItem(
                    title: title,
                    action: #selector(switchToSpaceFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = space.index
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload Config", action: #selector(refreshFromMenu), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let configItem = NSMenuItem(title: "Open Config…", action: #selector(openConfig), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        if config.disableAnimations {
            menu.addItem(NSMenuItem(title: "Instant switching (config)", action: nil, keyEquivalent: ""))
        }
        if config.disableSystemMotions {
            menu.addItem(NSMenuItem(title: "Trackpad, Control-arrows, and Command-Tab are instant (config)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Altitude", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshSpacesAndHotkeys() {
        lastSnapshot = spaceService.snapshot()
        hotkeys.apply(config: config, spaceCount: lastSnapshot.spaces.count)
        refreshIndicator()
        buildMenu()
    }

    private func refreshIndicator() {
        let axOK = focusResolver.isAccessibilityTrusted
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }

        if lastSnapshot.spaces.isEmpty {
            button.image = nil
            button.title = axOK ? "Alt" : "Alt!"
            button.imagePosition = .noImage
            return
        }

        button.image = SpaceIndicatorRenderer.image(snapshot: lastSnapshot)
        button.title = ""
        button.imagePosition = .imageOnly
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollSpaces()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func pollSpaces() {
        let snapshot = spaceService.snapshot()
        if snapshot.spaces.map(\.id) != lastSnapshot.spaces.map(\.id)
            || snapshot.currentIndex != lastSnapshot.currentIndex
        {
            lastSnapshot = snapshot
            hotkeys.apply(config: config, spaceCount: snapshot.spaces.count)
            refreshIndicator()
            buildMenu()
        }
        updateSystemMotions()
    }

    private func updateSystemMotions() {
        if config.disableSystemMotions {
            if motionSuppressor == nil {
                motionSuppressor = SystemMotionSuppressor(spaceService: spaceService)
            }
            motionSuppressor?.start()
        } else {
            motionSuppressor?.stop()
        }
    }

    private func observeWorkspace() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func spaceDidChange() {
        spaceService.acknowledgeSystemSpaceChange()
        refreshSpacesAndHotkeys()
    }
}
