import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
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

    private let container = NSView()
    private var panes: [Tab: NSView] = [:]

    // General
    private let launchAtLoginSwitch = NSSwitch()

    // Desktop
    private let desktopEnabledSwitch = NSSwitch()
    private let desktopDisableMotionSwitch = NSSwitch()
    private let maxSpaceStepper = NSStepper()
    private let maxSpaceField = NSTextField(labelWithString: "9")
    private let switchOption = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let switchShift = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let switchControl = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let switchCommand = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let moveOption = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let moveShift = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let moveControl = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let moveCommand = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
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
    private var windowsDependentControls: [NSView] = []

    init(menuBar: MenuBarController) {
        self.menuBar = menuBar
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.toolbarStyle = .preference
        window.setContentSize(NSSize(width: 440, height: 460))
        window.styleMask.remove(.resizable)
        window.setFrameAutosaveName("AltitudeSettings")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        buildPanes()
        installToolbar()
        showPane(.general)
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func display(_ config: AppConfig) {
        suppressActions = true
        defer { suppressActions = false }

        launchAtLoginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off

        desktopEnabledSwitch.state = config.desktop.enabled ? .on : .off
        desktopDisableMotionSwitch.state = config.desktop.disableMotion ? .on : .off
        maxSpaceStepper.integerValue = config.desktop.maxSpace
        maxSpaceField.stringValue = "\(config.desktop.maxSpace)"
        applyModifiers(config.desktop.switchModifiers, to: [switchOption, switchShift, switchControl, switchCommand])
        applyModifiers(config.desktop.moveModifiers, to: [moveOption, moveShift, moveControl, moveCommand])
        setEnabled(config.desktop.enabled, controls: desktopDependentControls)

        commandTabEnabledSwitch.state = config.commandTab.enabled ? .on : .off
        commandTabDisableMotionSwitch.state = config.commandTab.disableMotion ? .on : .off
        setEnabled(config.commandTab.enabled, controls: commandTabDependentControls)

        windowsEnabledSwitch.state = config.windowManagement.enabled ? .on : .off
        marginStepper.integerValue = config.windowManagement.margin
        marginField.stringValue = "\(config.windowManagement.margin)"
        maximizeRecorder.display(chord: config.windowManagement.maximize)
        equalSplitRecorder.display(chord: config.windowManagement.equalSplit)
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

        // Size the window to the Desktop pane (largest).
        if let desktop = panes[.desktop] {
            desktop.layoutSubtreeIfNeeded()
            let size = desktop.fittingSize
            window?.setContentSize(NSSize(width: max(440, size.width + 40), height: max(size.height + 24, 360)))
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

        let switchGroup = modifierGroup(
            title: "Switch modifiers",
            option: switchOption,
            shift: switchShift,
            control: switchControl,
            command: switchCommand
        )
        stack.addArrangedSubview(switchGroup)

        let moveGroup = modifierGroup(
            title: "Move modifiers",
            option: moveOption,
            shift: moveShift,
            control: moveControl,
            command: moveCommand
        )
        stack.addArrangedSubview(moveGroup)

        desktopDependentControls = [
            motionRow, maxRow, switchGroup, moveGroup,
            desktopDisableMotionSwitch, maxSpaceStepper,
            switchOption, switchShift, switchControl, switchCommand,
            moveOption, moveShift, moveControl, moveCommand,
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
            defaultButton: maximizeDefaultButton
        )
        stack.addArrangedSubview(maximizeRow)

        let equalRow = shortcutRow(
            title: "Equal columns",
            recorder: equalSplitRecorder,
            defaultButton: equalSplitDefaultButton
        )
        stack.addArrangedSubview(equalRow)

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
        let titleLabel = label(title)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView()) // spacer
        row.addArrangedSubview(switchControl)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func modifierGroup(
        title: String,
        option: NSButton,
        shift: NSButton,
        control: NSButton,
        command: NSButton
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(label(title))

        let checks = NSStackView()
        checks.orientation = .horizontal
        checks.spacing = 12
        for button in [option, shift, control, command] {
            checks.addArrangedSubview(button)
        }
        stack.addArrangedSubview(checks)

        let help = NSTextField(labelWithString: "Followed by 1–9")
        help.textColor = .secondaryLabelColor
        help.font = NSFont.systemFont(ofSize: 11)
        stack.addArrangedSubview(help)
        return stack
    }

    private func shortcutRow(title: String, recorder: ShortcutRecorderControl, defaultButton: NSButton) -> NSView {
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
        return stack
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

        for button in [switchOption, switchShift, switchControl, switchCommand,
                       moveOption, moveShift, moveControl, moveCommand] {
            button.target = self
            button.action = #selector(desktopModifiersChanged(_:))
        }

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

    @objc private func desktopModifiersChanged(_ sender: NSButton) {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        let proposedSwitch = readModifiers(from: [switchOption, switchShift, switchControl, switchCommand])
        let proposedMove = readModifiers(from: [moveOption, moveShift, moveControl, moveCommand])

        let isSwitch = [switchOption, switchShift, switchControl, switchCommand].contains(sender)
        if isSwitch {
            let validated = validatedDesktopModifiers(
                current: config.desktop.switchModifiers,
                other: config.desktop.moveModifiers,
                proposed: proposedSwitch
            )
            if validated == config.desktop.switchModifiers && proposedSwitch != config.desktop.switchModifiers {
                NSSound.beep()
                display(config)
                return
            }
            config.desktop.switchModifiers = validated
        } else {
            let validated = validatedDesktopModifiers(
                current: config.desktop.moveModifiers,
                other: config.desktop.switchModifiers,
                proposed: proposedMove
            )
            if validated == config.desktop.moveModifiers && proposedMove != config.desktop.moveModifiers {
                NSSound.beep()
                display(config)
                return
            }
            config.desktop.moveModifiers = validated
        }
        menuBar.apply(config, write: true)
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
        let validated = validatedWindowChord(
            current: config.windowManagement.maximize,
            other: config.windowManagement.equalSplit,
            proposed: proposed
        )
        if validated == config.windowManagement.maximize {
            if normalizedChord(proposed) != config.windowManagement.maximize {
                NSSound.beep()
            }
            display(config)
            return
        }
        config.windowManagement.maximize = validated
        menuBar.apply(config, write: true)
    }

    private func applyEqualSplit(_ proposed: KeyChord) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        let validated = validatedWindowChord(
            current: config.windowManagement.equalSplit,
            other: config.windowManagement.maximize,
            proposed: proposed
        )
        if validated == config.windowManagement.equalSplit {
            if normalizedChord(proposed) != config.windowManagement.equalSplit {
                NSSound.beep()
            }
            display(config)
            return
        }
        config.windowManagement.equalSplit = validated
        menuBar.apply(config, write: true)
    }

    @objc private func useMaximizeDefault() {
        applyMaximize(.maximizeDefault)
    }

    @objc private func useEqualSplitDefault() {
        applyEqualSplit(.equalSplitDefault)
    }

    private func normalizedChord(_ chord: KeyChord) -> KeyChord {
        KeyChord(
            modifiers: chord.modifiers,
            key: chord.key.lowercased().first ?? chord.key
        )
    }

    // MARK: - Helpers

    private func applyModifiers(_ flags: ModifierFlags, to buttons: [NSButton]) {
        buttons[0].state = flags.alt ? .on : .off
        buttons[1].state = flags.shift ? .on : .off
        buttons[2].state = flags.ctrl ? .on : .off
        buttons[3].state = flags.cmd ? .on : .off
    }

    private func readModifiers(from buttons: [NSButton]) -> ModifierFlags {
        ModifierFlags(
            alt: buttons[0].state == .on,
            shift: buttons[1].state == .on,
            ctrl: buttons[2].state == .on,
            cmd: buttons[3].state == .on
        )
    }

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
