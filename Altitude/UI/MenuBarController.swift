import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "MenuBar")

@MainActor
final class MenuBarController: NSObject {
    private static let didPromptForAccessibilityKey = "didPromptForAccessibility"

    private let statusItem: NSStatusItem
    private let spaceService: SpaceService
    private let focusResolver: AccessibilityTrusting
    private let configStore: ConfigPersisting
    private let launchAtLogin: LaunchAtLoginControlling
    private let arranger = WindowArranger()
    private let windowFocuser = WindowFocuser()
    private lazy var appShortcutJumper = AppShortcutJumper(
        spaceService: spaceService,
        focuser: windowFocuser
    )
    private lazy var hotkeys: HotkeyApplying = HotkeyRegistrar { [weak self] action in
        Task { @MainActor [weak self] in
            self?.handle(action: action)
        }
    }
    private var config: AppConfig
    private var configLoadFailed: Bool
    private var configModifiedAt: Date?
    private var pollTimer: Timer?
    private var lastSnapshot = SpaceSnapshot.empty
    private var lastAccessibilityTrusted: Bool?
    private var motionSuppressor: SystemMotionSuppressor?
    private lazy var settings: SettingsWindowController = SettingsWindowController(menuBar: self)

    var currentConfig: AppConfig { config }

    init(
        spaceService: SpaceService,
        focusResolver: AccessibilityTrusting,
        configStore: ConfigPersisting = ConfigStore.standard,
        launchAtLogin: LaunchAtLoginControlling = SystemLaunchAtLogin(),
        hotkeys: HotkeyApplying? = nil
    ) {
        self.spaceService = spaceService
        self.focusResolver = focusResolver
        self.configStore = configStore
        self.launchAtLogin = launchAtLogin
        let loadResult = configStore.load()
        switch loadResult {
        case .missing:
            self.config = .default
            self.configLoadFailed = false
            self.configModifiedAt = nil
        case .loaded(let loaded, let modifiedAt):
            self.config = loaded
            self.configLoadFailed = false
            self.configModifiedAt = modifiedAt
        case .failed:
            self.config = .default
            self.configLoadFailed = true
            self.configModifiedAt = nil
        }
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let hotkeys {
            self.hotkeys = hotkeys
        }
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
        if case .failed = loadResult {
            log.error("Config load failed during launch; keeping defaults and skipping Launch at Login reconcile")
        } else if !launchAtLogin.apply(desired: config.launchAtLogin) {
            log.error("Launch at Login reconcile failed during launch")
        }
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        startPolling()
        observeWorkspace()
        settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
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
            performSpaceHotkey { try spaceService.switchTo(index: index) }
        case .moveTo(let index):
            performSpaceHotkey { try spaceService.moveFocusedWindow(to: index) }
        case .jumpToApp(let index):
            guard config.appShortcuts.entries.indices.contains(index) else { return }
            appShortcutJumper.jump(toBundleID: config.appShortcuts.entries[index].bundleID)
        }
    }

    private func performSpaceHotkey(_ body: () throws -> Void) {
        do {
            try body()
            // Dock-swipe transitions settle after the gesture frames are posted.
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.hotkeyRefresh) { [weak self] in
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
        switch configStore.load() {
        case .loaded(let loaded, let modifiedAt):
            configLoadFailed = false
            configModifiedAt = modifiedAt
            apply(loaded, write: false)
        case .missing:
            configLoadFailed = false
            configModifiedAt = nil
            apply(.default, write: false)
        case .failed:
            configLoadFailed = true
            NSSound.beep()
            settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
            buildMenu()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(LaunchAtLogin.toggledDesired(
            isEnabled: launchAtLogin.isEnabled,
            requiresApproval: launchAtLogin.requiresApproval
        ))
    }

    @objc func showSettings() {
        settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
        settings.show()
    }

    /// Updates Launch at Login via SMAppService, writes config, and rolls back on failure.
    func setLaunchAtLogin(_ desired: Bool) {
        switch configSaveGuardDecision() {
        case .blocked:
            NSSound.beep()
            settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
            buildMenu()
            return
        case .reload:
            reloadConfigDroppingEdit()
            return
        case .proceed:
            break
        }

        let previous = config.launchAtLogin
        let outcome = MenuBarMutation.setLaunchAtLogin(
            desired: desired,
            previous: previous,
            setEnabled: { try launchAtLogin.setEnabled($0) },
            save: {
                self.config.launchAtLogin = desired
                try self.configStore.save(self.config)
            }
        )
        switch outcome {
        case .serviceFailed:
            log.error("Launch at Login toggle failed")
            NSSound.beep()
        case .saveFailedRestored(let restored):
            log.error("Could not write launch_at_login; restored login item")
            config.launchAtLogin = restored
            NSSound.beep()
        case .succeeded(let value):
            config.launchAtLogin = value
            configModifiedAt = configStore.resolvedModificationDate()
        }
        settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
        buildMenu()
    }

    /// Replaces in-memory config, optionally writes TOML, then reapplies hotkeys and motion.
    func apply(_ newConfig: AppConfig, write: Bool) {
        if write {
            switch configSaveGuardDecision() {
            case .blocked:
                NSSound.beep()
                settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
                buildMenu()
                return
            case .reload:
                reloadConfigDroppingEdit()
                return
            case .proceed:
                break
            }
        }

        let previous = config
        config = newConfig

        switch MenuBarMutation.applyWrite(write: write, save: { try self.configStore.save(self.config) }) {
        case .saveFailed:
            log.error("Could not write config")
            config = previous
            NSSound.beep()
            settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
            buildMenu()
            return
        case .succeeded:
            if write {
                configModifiedAt = configStore.resolvedModificationDate()
            }
        }

        spaceService.instantSwitching = DesktopFeature.instantSwitching(config: config)
        // Login-item edits use setLaunchAtLogin; other apply paths reconcile here.
        if !launchAtLogin.apply(desired: config.launchAtLogin) {
            log.error("Launch at Login reconcile failed")
            NSSound.beep()
        }
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
        buildMenu()
    }

    private func configSaveGuardDecision() -> ConfigSaveGuard {
        MenuBarMutation.configSaveGuard(
            loadFailed: configLoadFailed,
            recordedModifiedAt: configModifiedAt,
            currentModifiedAt: configStore.resolvedModificationDate()
        )
    }

    /// Reloads from disk after the save guard detects an external change. Never writes or reconciles Launch at Login.
    private func reloadConfigDroppingEdit() {
        switch configStore.load() {
        case .loaded(let loaded, let modifiedAt):
            config = loaded
            configModifiedAt = modifiedAt
            configLoadFailed = false
            reapplyRuntimeWithoutLoginReconcile()
            NSSound.beep()
        case .missing:
            config = .default
            configModifiedAt = nil
            configLoadFailed = false
            reapplyRuntimeWithoutLoginReconcile()
            NSSound.beep()
        case .failed:
            configLoadFailed = true
            NSSound.beep()
            settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
            buildMenu()
        }
    }

    private func reapplyRuntimeWithoutLoginReconcile() {
        spaceService.instantSwitching = DesktopFeature.instantSwitching(config: config)
        updateSystemMotions()
        refreshSpacesAndHotkeys()
        settings.display(config, launchAtLoginEnabled: launchAtLogin.isEnabled)
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

        if configLoadFailed {
            let failed = NSMenuItem(title: "Config was not loaded", action: nil, keyEquivalent: "")
            failed.isEnabled = false
            menu.addItem(failed)
        }

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
        launchItem.state = launchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let quitItem = NSMenuItem(title: "Quit Altitude", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshSpacesAndHotkeys() {
        lastSnapshot = spaceService.snapshot()
        let bindings = DesktopFeature.bindings(config: config, spaceCount: lastSnapshot.spaces.count)
            + WindowManagementFeature.bindings(config: config)
            + AppShortcutsFeature.bindings(config: config)
        hotkeys.apply(bindings)
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
            Task { @MainActor [weak self] in
                self?.pollSpaces()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func pollSpaces() {
        let trusted = focusResolver.isAccessibilityTrusted
        if trusted != lastAccessibilityTrusted {
            lastAccessibilityTrusted = trusted
            refreshIndicator()
            buildMenu()
        }
        let snapshot = spaceService.snapshot()
        if snapshot.spaces.map(\.id) != lastSnapshot.spaces.map(\.id)
            || snapshot.currentIndex != lastSnapshot.currentIndex
        {
            lastSnapshot = snapshot
            let bindings = DesktopFeature.bindings(config: config, spaceCount: snapshot.spaces.count)
                + WindowManagementFeature.bindings(config: config)
                + AppShortcutsFeature.bindings(config: config)
            hotkeys.apply(bindings)
            refreshIndicator()
            buildMenu()
        }
        // Runs every second so taps install once Accessibility is granted.
        updateSystemMotions()
    }

    private func updateSystemMotions() {
        let mode = CommandTabFeature.motionMode(config: config)
        if mode.wantsTaps {
            if motionSuppressor == nil {
                motionSuppressor = SystemMotionSuppressor(
                    spaceService: spaceService,
                    focuser: windowFocuser
                )
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
