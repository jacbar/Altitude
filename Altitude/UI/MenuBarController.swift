import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "MenuBar")

@MainActor
final class MenuBarController: NSObject, @unchecked Sendable {
    private static let didPromptForAccessibilityKey = "didPromptForAccessibility"

    /// Waits for dock-swipe gesture frames to land before refreshing Spaces/hotkeys.
    private let hotkeyRefreshDelay: TimeInterval = 0.45

    private let statusItem: NSStatusItem
    private let spaceService: SpaceService
    private let focusResolver: FocusedWindowResolver
    private let arranger = WindowArranger()
    private let hotkeys: HotkeyRegistrar
    private var config: AppConfig
    private var pollTimer: Timer?
    private var lastSnapshot = SpaceSnapshot.empty
    private var motionSuppressor: SystemMotionSuppressor?
    private let settings: SettingsWindowController
    private var failedHotkeys: [HotkeyBinding] = []

    var currentConfig: AppConfig { config }

    init(spaceService: SpaceService, focusResolver: FocusedWindowResolver) {
        self.spaceService = spaceService
        self.focusResolver = focusResolver
        self.config = ConfigStore.load()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        nonisolated(unsafe) weak var controller: MenuBarController?
        self.hotkeys = HotkeyRegistrar { action in
            Task { @MainActor in
                controller?.handle(action: action)
            }
        }
        self.settings = SettingsWindowController()
        super.init()
        controller = self
        settings.attach(menuBar: self)

        AppMenu.install(target: self)

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

        spaceService.instantSwitching = DesktopFeature.instantSwitching(config: config)
        if !LaunchAtLogin.apply(desired: config.launchAtLogin) {
            log.error("Launch at Login reconcile failed during launch")
        }
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        startPolling()
        observeWorkspace()
        settings.display(config, failedHotkeys: failedHotkeys)
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
        switch action {
        case .maximizeAll:
            arrangeWindows(.maximize)
        case .tileColumns:
            arrangeWindows(.columns)
        case .switchTo(let index):
            performSpaceAction {
                try spaceService.switchTo(index: index)
            }
        case .moveTo(let index):
            performSpaceAction {
                try spaceService.moveFocusedWindow(to: index)
            }
        }
    }

    private func performSpaceAction(_ body: () throws -> Void) {
        do {
            try body()
            DispatchQueue.main.asyncAfter(deadline: .now() + hotkeyRefreshDelay) { [weak self] in
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

    private func arrangeWindows(_ action: ArrangeAction) {
        guard focusResolver.isAccessibilityTrusted else {
            log.error("Accessibility required for window arrangement")
            NSSound.beep()
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen, let spaceID = spaceService.currentSpaceID(on: screen) else {
            log.error("Could not resolve Space for window arrangement")
            NSSound.beep()
            return
        }
        let margin = WindowManagementFeature.margin(config: config)
        switch arranger.arrange(action, margin: margin, on: spaceID, screen: screen) {
        case .applied(let count):
            log.info("Arranged \(count) window(s)")
        case .accessibilityDenied, .nothingToDo:
            NSSound.beep()
        }
    }

    @objc private func refreshFromMenu() {
        let loaded = ConfigStore.load()
        apply(loaded, write: false)
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(LaunchAtLogin.toggledDesired)
    }

    @objc func showSettings() {
        settings.display(config, failedHotkeys: failedHotkeys)
        settings.show()
    }

    /// Updates Launch at Login via SMAppService, writes config, and rolls back on failure.
    func setLaunchAtLogin(_ desired: Bool) {
        config = ConfigApply.setLaunchAtLogin(
            desired: desired,
            config: config,
            setEnabled: LaunchAtLogin.setEnabled,
            save: ConfigStore.save
        )
        if config.launchAtLogin != desired {
            log.error("Launch at Login toggle failed or could not be saved")
            NSSound.beep()
        }
        settings.display(config, failedHotkeys: failedHotkeys)
        buildMenu()
    }

    /// Replaces in-memory config, optionally writes TOML, then reapplies hotkeys and motion.
    func apply(_ newConfig: AppConfig, write: Bool) {
        let previous = config

        if write {
            let saved = ConfigApply.saving(
                previous: previous,
                updated: newConfig,
                save: ConfigStore.save
            )
            if saved != newConfig {
                log.error("Could not write config")
                NSSound.beep()
                settings.display(config, failedHotkeys: failedHotkeys)
                buildMenu()
                return
            }
            config = saved
        } else {
            config = newConfig
        }

        spaceService.instantSwitching = DesktopFeature.instantSwitching(config: config)
        // Login-item edits use setLaunchAtLogin; other apply paths reconcile here.
        if !LaunchAtLogin.apply(desired: config.launchAtLogin) {
            log.error("Launch at Login reconcile failed")
            NSSound.beep()
        }
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        settings.display(config, failedHotkeys: failedHotkeys)
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

        if config.desktop.enabled {
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
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reload = NSMenuItem(title: "Reload Config", action: #selector(refreshFromMenu), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let configItem = NSMenuItem(title: "Open Config…", action: #selector(openConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        if DesktopFeature.instantSwitching(config: config) {
            menu.addItem(NSMenuItem(title: "Desktop motion on", action: nil, keyEquivalent: ""))
        }
        if config.commandTab.enabled {
            menu.addItem(NSMenuItem(title: "Command-Tab on", action: nil, keyEquivalent: ""))
        }
        if config.commandTab.enabled && config.commandTab.disableMotion {
            menu.addItem(NSMenuItem(title: "Command-Tab landing skips the slide", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        // Only show checked when fully enabled; requiresApproval stays unchecked honestly.
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let quitItem = NSMenuItem(title: "Quit Altitude", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshSpacesAndHotkeys() {
        lastSnapshot = spaceService.snapshot()
        applyHotkeyBindings(
            DesktopFeature.bindings(config: config, spaceCount: lastSnapshot.spaces.count)
                + WindowManagementFeature.bindings(config: config)
        )
        refreshIndicator()
        buildMenu()
    }

    private func applyHotkeyBindings(_ bindings: [HotkeyBinding]) {
        let failed = hotkeys.apply(bindings)
        if failed != failedHotkeys {
            if !failed.isEmpty {
                NSSound.beep()
            }
            failedHotkeys = failed
        }
        settings.display(config, failedHotkeys: failedHotkeys)
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
            Task { @MainActor [weak self] in
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
            applyHotkeyBindings(
                DesktopFeature.bindings(config: config, spaceCount: snapshot.spaces.count)
                    + WindowManagementFeature.bindings(config: config)
            )
            refreshIndicator()
            buildMenu()
        }
        // updateSystemMotions() every tick so taps install on the first poll after Accessibility is granted.
        updateSystemMotions()
    }

    private func updateSystemMotions() {
        let mode = CommandTabFeature.motionMode(config: config)
        if mode.wantsTaps {
            if motionSuppressor == nil {
                motionSuppressor = SystemMotionSuppressor(spaceService: spaceService)
            }
            motionSuppressor?.apply(mode)
        } else {
            motionSuppressor?.apply(.off)
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
