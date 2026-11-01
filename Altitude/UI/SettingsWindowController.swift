import AppKit
import ApplicationServices

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case desktop = "Desktop"
        case commandTab = "Command-Tab"
        case windows = "Windows"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .desktop: return "rectangle.3.group"
            case .commandTab: return "command"
            case .windows: return "rectangle.split.3x1"
            }
        }
    }

    private weak var menuBar: MenuBarController?
    private var suppressActions = false
    private var selectedTab: Tab = .general
    private static let frameAutosaveName = "AltitudeSettings"
    private static let frameAutosaveDefaultsKey = "NSWindow Frame AltitudeSettings"

    private let container = NSView()
    private var panes: [Tab: NSView] = [:]

    // General
    private let launchAtLoginSwitch = NSSwitch()

    // Desktop
    private let desktopEnabledSwitch = NSSwitch()
    private let desktopDisableMotionSwitch = NSSwitch()
    private let maxSpaceStepper = NSStepper()
    private let maxSpaceField = NSTextField(labelWithString: "9")
    private let switchRecorder = ShortcutRecorderControl()
    private let moveRecorder = ShortcutRecorderControl()
    private let switchDefaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let moveDefaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let switchConflictLabel = SettingsWindowController.conflictLabel()
    private let moveConflictLabel = SettingsWindowController.conflictLabel()
    private let desktopRegistrationLabel = SettingsWindowController.conflictLabel()
    private var desktopDependentControls: [NSView] = []

    // Command-Tab
    private let commandTabEnabledSwitch = NSSwitch()
    private let commandTabDisableMotionSwitch = NSSwitch()
    private var commandTabDependentControls: [NSView] = []

    // Windows
    private let windowsEnabledSwitch = NSSwitch()
    private let marginStepper = NSStepper()
    private let marginField = NSTextField(labelWithString: "8")
    private let maximizeRecorder = ShortcutRecorderControl()
    private let equalSplitRecorder = ShortcutRecorderControl()
    private let maximizeDefaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let equalSplitDefaultButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let maximizeConflictLabel = SettingsWindowController.conflictLabel()
    private let equalSplitConflictLabel = SettingsWindowController.conflictLabel()
    private let windowsRegistrationLabel = SettingsWindowController.conflictLabel()
    private var windowsDependentControls: [NSView] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.toolbarStyle = .preference
        window.styleMask.remove(.resizable)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildPanes()
        installToolbar()
        showPane(.general)
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(menuBar: MenuBarController) {
        self.menuBar = menuBar
    }

    func show() {
        // Status-item menus track the mouse on a nested run-loop turn. Policy and
        // activation changes made mid-tracking are ignored; present after dismiss.
        DispatchQueue.main.async { [weak self] in
            self?.presentSettings()
        }
    }

    private func presentSettings() {
        guard let window else { return }

        becomeForegroundApp()
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // setFrameAutosaveName(_:) restores any saved frame when assigned — that was
        // undoing centering when called after setFrame. Restore first if usable;
        // otherwise center, bind autosave, then re-center (bind can re-apply a save).
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
            && isUsablePlacedFrame(window.frame)
        if !restored {
            UserDefaults.standard.removeObject(forKey: Self.frameAutosaveDefaultsKey)
            centerOnActiveScreen(window)
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !restored {
            centerOnActiveScreen(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: Self.frameAutosaveName)
        becomeAccessoryApp()
    }

    /// Rejects the default bottom-left origin, off-screen frames, and oversized frames
    /// (unconstrained stack fittingSize can match the display and clamp to 0,0).
    private func isUsablePlacedFrame(_ frame: NSRect) -> Bool {
        if frame.origin.x < 2, frame.origin.y < 2 { return false }
        if frame.width > 700 || frame.height > 800 { return false }
        return NSScreen.screens.contains { screen in
            screen.visibleFrame.intersection(frame).width > 80
                && screen.visibleFrame.intersection(frame).height > 80
        }
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = NSSize(width: 480, height: 520)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
    }

    private func becomeForegroundApp() {
        // Policy alone is not enough for an LSUIElement agent: the process type has to
        // be transformed as well or the Settings window stays stuck behind other apps.
        _ = NSApp.setActivationPolicy(.regular)
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    }

    private func becomeAccessoryApp() {
        // Mirror becomeForegroundApp: both policy and process-type transform are required.
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func display(_ config: AppConfig, failedHotkeys: [HotkeyBinding] = []) {
        suppressActions = true
        defer { suppressActions = false }

        launchAtLoginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off

        desktopEnabledSwitch.state = config.desktop.enabled ? .on : .off
        desktopDisableMotionSwitch.state = config.desktop.disableMotion ? .on : .off
        maxSpaceStepper.integerValue = config.desktop.maxSpace
        maxSpaceField.stringValue = "\(config.desktop.maxSpace)"
        switchRecorder.display(modifiers: config.desktop.switchModifiers)
        moveRecorder.display(modifiers: config.desktop.moveModifiers)
        clearConflict(switchConflictLabel)
        clearConflict(moveConflictLabel)
        let desktopRegistrationFailed = failedHotkeys.contains {
            switch $0.action {
            case .switchTo, .moveTo: return true
            case .maximizeAll, .tileColumns: return false
            }
        }
        setRegistrationLabel(desktopRegistrationLabel, visible: desktopRegistrationFailed)
        setEnabled(config.desktop.enabled, controls: desktopDependentControls)

        commandTabEnabledSwitch.state = config.commandTab.enabled ? .on : .off
        commandTabDisableMotionSwitch.state = config.commandTab.disableMotion ? .on : .off
        setEnabled(config.commandTab.enabled, controls: commandTabDependentControls)

        windowsEnabledSwitch.state = config.windowManagement.enabled ? .on : .off
        marginStepper.integerValue = config.windowManagement.margin
        marginField.stringValue = "\(config.windowManagement.margin)"
        maximizeRecorder.display(chord: config.windowManagement.maximize)
        equalSplitRecorder.display(chord: config.windowManagement.equalSplit)
        clearConflict(maximizeConflictLabel)
        clearConflict(equalSplitConflictLabel)
        let windowsRegistrationFailed = failedHotkeys.contains {
            switch $0.action {
            case .maximizeAll, .tileColumns: return true
            case .switchTo, .moveTo: return false
            }
        }
        setRegistrationLabel(windowsRegistrationLabel, visible: windowsRegistrationFailed)
        setEnabled(config.windowManagement.enabled, controls: windowsDependentControls)
    }

    // MARK: - Build

    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "AltitudeSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(Tab.general.rawValue)
        window?.toolbar = toolbar
    }

    private func buildPanes() {
        guard let content = window?.contentView else { return }
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.topAnchor.constraint(equalTo: content.topAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        panes[.general] = makeGeneralPane()
        panes[.desktop] = makeDesktopPane()
        panes[.commandTab] = makeCommandTabPane()
        panes[.windows] = makeWindowsPane()

        // Size to the Desktop pane (largest). Cap width: horizontal stacks use a
        // flexible spacer whose fittingSize can match the full display width.
        if let desktop = panes[.desktop] {
            desktop.layoutSubtreeIfNeeded()
            let size = desktop.fittingSize
            let width = min(max(440, size.width + 40), 560)
            let height = min(max(360, size.height + 24), 640)
            window?.setContentSize(NSSize(width: width, height: height))
        } else {
            window?.setContentSize(NSSize(width: 480, height: 520))
        }
    }

    private func showPane(_ tab: Tab) {
        selectedTab = tab
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let pane = panes[tab] else { return }
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            pane.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            pane.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
    }

    private func makeGeneralPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.addArrangedSubview(labeledSwitchRow(title: "Launch at Login", switchControl: launchAtLoginSwitch))
        return stack
    }

    private func makeDesktopPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        stack.addArrangedSubview(labeledSwitchRow(title: "Desktop module", switchControl: desktopEnabledSwitch))

        let motionRow = labeledSwitchRow(title: "Skip the slide", switchControl: desktopDisableMotionSwitch)
        stack.addArrangedSubview(motionRow)

        let maxRow = NSStackView()
        maxRow.orientation = .horizontal
        maxRow.spacing = 8
        maxRow.addArrangedSubview(label("Highest desktop number"))
        maxSpaceField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        maxSpaceField.alignment = .right
        maxSpaceField.widthAnchor.constraint(equalToConstant: 24).isActive = true
        maxSpaceStepper.minValue = 1
        maxSpaceStepper.maxValue = 9
        maxSpaceStepper.increment = 1
        maxSpaceStepper.valueWraps = false
        maxRow.addArrangedSubview(maxSpaceField)
        maxRow.addArrangedSubview(maxSpaceStepper)
        stack.addArrangedSubview(maxRow)

        switchRecorder.mode = .modifiersOnly
        moveRecorder.mode = .modifiersOnly

        let switchRow = shortcutRow(
            title: "Switch",
            recorder: switchRecorder,
            defaultButton: switchDefaultButton,
            help: "Followed by 1–9",
            conflictLabel: switchConflictLabel
        )
        stack.addArrangedSubview(switchRow)

        let moveRow = shortcutRow(
            title: "Move focused window",
            recorder: moveRecorder,
            defaultButton: moveDefaultButton,
            help: "Followed by 1–9",
            conflictLabel: moveConflictLabel
        )
        stack.addArrangedSubview(moveRow)
        stack.addArrangedSubview(desktopRegistrationLabel)

        desktopDependentControls = [
            motionRow, maxRow, switchRow, moveRow,
            desktopDisableMotionSwitch, maxSpaceStepper,
            switchRecorder, moveRecorder,
            switchDefaultButton, moveDefaultButton,
        ]
        return stack
    }

    private func makeCommandTabPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.addArrangedSubview(labeledSwitchRow(title: "Command-Tab module", switchControl: commandTabEnabledSwitch))
        let motionRow = labeledSwitchRow(title: "Skip the slide when landing", switchControl: commandTabDisableMotionSwitch)
        stack.addArrangedSubview(motionRow)
        commandTabDependentControls = [motionRow, commandTabDisableMotionSwitch]
        return stack
    }

    private func makeWindowsPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        stack.addArrangedSubview(labeledSwitchRow(title: "Windows module", switchControl: windowsEnabledSwitch))

        let marginRow = NSStackView()
        marginRow.orientation = .horizontal
        marginRow.spacing = 8
        marginRow.addArrangedSubview(label("Margin"))
        marginField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        marginField.alignment = .right
        marginField.widthAnchor.constraint(equalToConstant: 36).isActive = true
        marginStepper.minValue = 0
        marginStepper.maxValue = 256
        marginStepper.increment = 1
        marginStepper.valueWraps = false
        marginRow.addArrangedSubview(marginField)
        marginRow.addArrangedSubview(label("pt"))
        marginRow.addArrangedSubview(marginStepper)
        stack.addArrangedSubview(marginRow)

        let maximizeRow = shortcutRow(
            title: "Maximize",
            recorder: maximizeRecorder,
            defaultButton: maximizeDefaultButton,
            conflictLabel: maximizeConflictLabel
        )
        stack.addArrangedSubview(maximizeRow)

        let equalRow = shortcutRow(
            title: "Equal columns",
            recorder: equalSplitRecorder,
            defaultButton: equalSplitDefaultButton,
            conflictLabel: equalSplitConflictLabel
        )
        stack.addArrangedSubview(equalRow)
        stack.addArrangedSubview(windowsRegistrationLabel)

        windowsDependentControls = [
            marginRow, maximizeRow, equalRow,
            marginStepper, maximizeRecorder, equalSplitRecorder,
            maximizeDefaultButton, equalSplitDefaultButton,
        ]
        return stack
    }

    private func labeledSwitchRow(title: String, switchControl: NSSwitch) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.distribution = .fill
        let titleLabel = label(title)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        switchControl.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(switchControl)
        return row
    }

    private func shortcutRow(
        title: String,
        recorder: ShortcutRecorderControl,
        defaultButton: NSButton,
        help: String? = nil,
        conflictLabel: NSTextField? = nil
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(label(title))

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        defaultButton.bezelStyle = .rounded
        row.addArrangedSubview(recorder)
        row.addArrangedSubview(defaultButton)
        stack.addArrangedSubview(row)

        if let help {
            let helpLabel = NSTextField(labelWithString: help)
            helpLabel.textColor = .secondaryLabelColor
            helpLabel.font = NSFont.systemFont(ofSize: 11)
            stack.addArrangedSubview(helpLabel)
        }
        if let conflictLabel {
            stack.addArrangedSubview(conflictLabel)
        }
        return stack
    }

    private static func conflictLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.textColor = .systemRed
        field.font = NSFont.systemFont(ofSize: 11)
        field.isHidden = true
        return field
    }

    private func showConflict(_ label: NSTextField) {
        label.stringValue = "already in use"
        label.isHidden = false
    }

    private func clearConflict(_ label: NSTextField) {
        label.stringValue = ""
        label.isHidden = true
    }

    private func setRegistrationLabel(_ label: NSTextField, visible: Bool) {
        if visible {
            label.stringValue = "Could not register (in use by another app)"
            label.isHidden = false
        } else {
            clearConflict(label)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 13)
        return field
    }

    // MARK: - Actions

    private func wireActions() {
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)

        desktopEnabledSwitch.target = self
        desktopEnabledSwitch.action = #selector(desktopChanged)
        desktopDisableMotionSwitch.target = self
        desktopDisableMotionSwitch.action = #selector(desktopChanged)
        maxSpaceStepper.target = self
        maxSpaceStepper.action = #selector(maxSpaceChanged)

        switchRecorder.onRecordModifiers = { [weak self] modifiers in
            self?.applySwitchModifiers(modifiers)
        }
        moveRecorder.onRecordModifiers = { [weak self] modifiers in
            self?.applyMoveModifiers(modifiers)
        }
        switchDefaultButton.target = self
        switchDefaultButton.action = #selector(useSwitchDefault)
        moveDefaultButton.target = self
        moveDefaultButton.action = #selector(useMoveDefault)

        commandTabEnabledSwitch.target = self
        commandTabEnabledSwitch.action = #selector(commandTabChanged)
        commandTabDisableMotionSwitch.target = self
        commandTabDisableMotionSwitch.action = #selector(commandTabChanged)

        windowsEnabledSwitch.target = self
        windowsEnabledSwitch.action = #selector(windowsChanged)
        marginStepper.target = self
        marginStepper.action = #selector(marginChanged)

        maximizeRecorder.onRecord = { [weak self] chord in
            self?.applyMaximize(chord)
        }
        equalSplitRecorder.onRecord = { [weak self] chord in
            self?.applyEqualSplit(chord)
        }
        maximizeDefaultButton.target = self
        maximizeDefaultButton.action = #selector(useMaximizeDefault)
        equalSplitDefaultButton.target = self
        equalSplitDefaultButton.action = #selector(useEqualSplitDefault)
    }

    @objc private func launchAtLoginChanged() {
        guard !suppressActions, let menuBar else { return }
        menuBar.setLaunchAtLogin(launchAtLoginSwitch.state == .on)
    }

    @objc private func desktopChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.desktop.enabled = desktopEnabledSwitch.state == .on
        config.desktop.disableMotion = desktopDisableMotionSwitch.state == .on
        menuBar.apply(config, write: true)
    }

    @objc private func maxSpaceChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.desktop.maxSpace = maxSpaceStepper.integerValue
        maxSpaceField.stringValue = "\(config.desktop.maxSpace)"
        menuBar.apply(config, write: true)
    }

    private func applySwitchModifiers(_ proposed: ModifierFlags) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        switch validatedDesktopModifiers(
            other: config.desktop.moveModifiers,
            proposed: proposed
        ) {
        case .accepted(let value):
            clearConflict(switchConflictLabel)
            config.desktop.switchModifiers = value
            menuBar.apply(config, write: true)
        case .conflict:
            NSSound.beep()
            showConflict(switchConflictLabel)
            switchRecorder.display(modifiers: config.desktop.switchModifiers)
        case .invalid:
            NSSound.beep()
            switchRecorder.display(modifiers: config.desktop.switchModifiers)
        }
    }

    private func applyMoveModifiers(_ proposed: ModifierFlags) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        switch validatedDesktopModifiers(
            other: config.desktop.switchModifiers,
            proposed: proposed
        ) {
        case .accepted(let value):
            clearConflict(moveConflictLabel)
            config.desktop.moveModifiers = value
            menuBar.apply(config, write: true)
        case .conflict:
            NSSound.beep()
            showConflict(moveConflictLabel)
            moveRecorder.display(modifiers: config.desktop.moveModifiers)
        case .invalid:
            NSSound.beep()
            moveRecorder.display(modifiers: config.desktop.moveModifiers)
        }
    }

    @objc private func useSwitchDefault() {
        applySwitchModifiers(.optionOnly)
    }

    @objc private func useMoveDefault() {
        applyMoveModifiers(.optionShift)
    }

    @objc private func commandTabChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.commandTab.enabled = commandTabEnabledSwitch.state == .on
        config.commandTab.disableMotion = commandTabDisableMotionSwitch.state == .on
        menuBar.apply(config, write: true)
    }

    @objc private func windowsChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.windowManagement.enabled = windowsEnabledSwitch.state == .on
        menuBar.apply(config, write: true)
    }

    @objc private func marginChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.windowManagement.margin = marginStepper.integerValue
        marginField.stringValue = "\(config.windowManagement.margin)"
        menuBar.apply(config, write: true)
    }

    private func applyMaximize(_ proposed: KeyChord) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        switch validatedWindowChord(
            other: config.windowManagement.equalSplit,
            proposed: proposed
        ) {
        case .accepted(let value):
            clearConflict(maximizeConflictLabel)
            config.windowManagement.maximize = value
            menuBar.apply(config, write: true)
        case .conflict:
            NSSound.beep()
            showConflict(maximizeConflictLabel)
            maximizeRecorder.display(chord: config.windowManagement.maximize)
        case .invalid:
            NSSound.beep()
            maximizeRecorder.display(chord: config.windowManagement.maximize)
        }
    }

    private func applyEqualSplit(_ proposed: KeyChord) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        switch validatedWindowChord(
            other: config.windowManagement.maximize,
            proposed: proposed
        ) {
        case .accepted(let value):
            clearConflict(equalSplitConflictLabel)
            config.windowManagement.equalSplit = value
            menuBar.apply(config, write: true)
        case .conflict:
            NSSound.beep()
            showConflict(equalSplitConflictLabel)
            equalSplitRecorder.display(chord: config.windowManagement.equalSplit)
        case .invalid:
            NSSound.beep()
            equalSplitRecorder.display(chord: config.windowManagement.equalSplit)
        }
    }

    @objc private func useMaximizeDefault() {
        applyMaximize(.maximizeDefault)
    }

    @objc private func useEqualSplitDefault() {
        applyEqualSplit(.equalSplitDefault)
    }

    // MARK: - Helpers

    private func setEnabled(_ enabled: Bool, controls: [NSView]) {
        for control in controls {
            if let control = control as? NSControl {
                control.isEnabled = enabled
            } else {
                for sub in control.subviews {
                    if let c = sub as? NSControl { c.isEnabled = enabled }
                }
            }
        }
    }

    // MARK: - Toolbar

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.paletteLabel = tab.rawValue
        item.toolTip = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.rawValue)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        window?.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        showPane(tab)
    }
}
