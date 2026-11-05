import AppKit
import ApplicationServices
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case desktop = "Desktop"
        case commandTab = "Command-Tab"
        case windows = "Windows"
        case appShortcuts = "App Shortcuts"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .desktop: return "rectangle.3.group"
            case .commandTab: return "command"
            case .windows: return "rectangle.split.3x1"
            case .appShortcuts: return "app.badge.checkmark"
            }
        }
    }

    private final class AppShortcutRowViews {
        let container: NSView
        let iconView: NSImageView
        let chooseAppButton: NSButton
        let recorder: ShortcutRecorderControl
        let removeButton: NSButton
        let conflictLabel: NSTextField
        var index: Int

        init(
            container: NSView,
            iconView: NSImageView,
            chooseAppButton: NSButton,
            recorder: ShortcutRecorderControl,
            removeButton: NSButton,
            conflictLabel: NSTextField,
            index: Int
        ) {
            self.container = container
            self.iconView = iconView
            self.chooseAppButton = chooseAppButton
            self.recorder = recorder
            self.removeButton = removeButton
            self.conflictLabel = conflictLabel
            self.index = index
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
    private var windowsDependentControls: [NSView] = []

    // App Shortcuts
    private let appShortcutsEnabledSwitch = NSSwitch()
    private let appShortcutsListBox = NSBox()
    private let appShortcutsRowsStack = NSStackView()
    private let appShortcutsEmptyLabel = NSTextField(
        labelWithString: "No shortcuts yet"
    )
    private let appShortcutsAddButton = NSButton(title: "Add Shortcut", target: nil, action: nil)
    private var appShortcutRows: [AppShortcutRowViews] = []
    private var appShortcutsDependentControls: [NSView] = []
    private var appShortcutsScrollView: NSScrollView?
    private var appShortcutsDocumentWidthConstraint: NSLayoutConstraint?

    init(menuBar: MenuBarController) {
        self.menuBar = menuBar
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
        // Both stay: setActivationPolicy updates AppKit; TransformProcessType updates the process for the Dock/Cmd-Tab.
        _ = NSApp.setActivationPolicy(.regular)
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    }

    private func becomeAccessoryApp() {
        // Both stay: TransformProcessType returns to UIElement; setActivationPolicy restores .accessory for AppKit.
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func display(_ config: AppConfig, launchAtLoginEnabled: Bool) {
        suppressActions = true
        defer { suppressActions = false }

        launchAtLoginSwitch.state = launchAtLoginEnabled ? .on : .off

        desktopEnabledSwitch.state = config.desktop.enabled ? .on : .off
        desktopDisableMotionSwitch.state = config.desktop.disableMotion ? .on : .off
        maxSpaceStepper.integerValue = config.desktop.maxSpace
        maxSpaceField.stringValue = "\(config.desktop.maxSpace)"
        switchRecorder.display(modifiers: config.desktop.switchModifiers)
        moveRecorder.display(modifiers: config.desktop.moveModifiers)
        clearConflict(switchConflictLabel)
        clearConflict(moveConflictLabel)
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
        setEnabled(config.windowManagement.enabled, controls: windowsDependentControls)

        refreshAppShortcutsPane(with: config)
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
        panes[.appShortcuts] = makeAppShortcutsPane()

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
        // Scroll document layout is wrong while this pane is off-screen; rebuild when shown,
        // then again after the next layout pass so the clip width is non-zero.
        if tab == .appShortcuts, let menuBar {
            refreshAppShortcutsPane(with: menuBar.currentConfig)
            DispatchQueue.main.async { [weak self] in
                guard let self, let menuBar = self.menuBar else { return }
                self.refreshAppShortcutsPane(with: menuBar.currentConfig)
            }
        }
    }

    private func refreshAppShortcutsPane(with config: AppConfig) {
        appShortcutsEnabledSwitch.state = config.appShortcuts.enabled ? .on : .off
        rebuildAppShortcutRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: appShortcutsDependentControls)
        appShortcutsAddButton.isEnabled = config.appShortcuts.enabled
            && config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts
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

        windowsDependentControls = [
            marginRow, maximizeRow, equalRow,
            marginStepper, maximizeRecorder, equalSplitRecorder,
            maximizeDefaultButton, equalSplitDefaultButton,
        ]
        return stack
    }

    private func makeAppShortcutsPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(
            labeledSwitchRow(title: "App Shortcuts module", switchControl: appShortcutsEnabledSwitch)
        )

        let help = NSTextField(
            labelWithString: "Jump to an app’s Space instantly. Already frontmost does nothing."
        )
        help.textColor = .secondaryLabelColor
        help.font = NSFont.systemFont(ofSize: 11)
        help.maximumNumberOfLines = 2
        help.preferredMaxLayoutWidth = 420
        stack.addArrangedSubview(help)

        appShortcutsListBox.boxType = .custom
        appShortcutsListBox.titlePosition = .noTitle
        appShortcutsListBox.cornerRadius = 10
        appShortcutsListBox.borderWidth = 1
        appShortcutsListBox.borderColor = .separatorColor
        appShortcutsListBox.fillColor = .controlBackgroundColor
        appShortcutsListBox.contentViewMargins = NSSize(width: 0, height: 0)
        appShortcutsListBox.translatesAutoresizingMaskIntoConstraints = false
        appShortcutsListBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        appShortcutsListBox.heightAnchor.constraint(equalToConstant: 248).isActive = true

        appShortcutsEmptyLabel.textColor = .secondaryLabelColor
        appShortcutsEmptyLabel.font = NSFont.systemFont(ofSize: 13)
        appShortcutsEmptyLabel.alignment = .center
        appShortcutsEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        appShortcutsRowsStack.orientation = .vertical
        appShortcutsRowsStack.alignment = .leading
        appShortcutsRowsStack.spacing = 0
        appShortcutsRowsStack.detachesHiddenViews = true
        appShortcutsRowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = appShortcutsRowsStack
        appShortcutsScrollView = scroll

        let clip = scroll.contentView
        let widthConstraint = appShortcutsRowsStack.widthAnchor.constraint(equalToConstant: 420)
        appShortcutsDocumentWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            appShortcutsRowsStack.topAnchor.constraint(equalTo: clip.topAnchor),
            appShortcutsRowsStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            widthConstraint,
        ])

        if let content = appShortcutsListBox.contentView {
            content.addSubview(scroll)
            content.addSubview(appShortcutsEmptyLabel)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: content.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                appShortcutsEmptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                appShortcutsEmptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                appShortcutsEmptyLabel.leadingAnchor.constraint(
                    greaterThanOrEqualTo: content.leadingAnchor,
                    constant: 16
                ),
                appShortcutsEmptyLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: content.trailingAnchor,
                    constant: -16
                ),
            ])
        }
        stack.addArrangedSubview(appShortcutsListBox)

        let addConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")?
            .withSymbolConfiguration(addConfig)
        {
            appShortcutsAddButton.image = plus
            appShortcutsAddButton.imagePosition = .imageLeading
        }
        appShortcutsAddButton.bezelStyle = .rounded
        stack.addArrangedSubview(appShortcutsAddButton)

        appShortcutsDependentControls = [
            help, appShortcutsListBox, appShortcutsAddButton,
        ]
        return stack
    }

    private func rebuildAppShortcutRows(entries: [AppShortcutEntry]) {
        appShortcutsRowsStack.arrangedSubviews.forEach {
            appShortcutsRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        appShortcutRows.removeAll()

        let enabled = appShortcutsEnabledSwitch.state == .on
        let isEmpty = entries.isEmpty
        appShortcutsEmptyLabel.isHidden = !isEmpty
        appShortcutsScrollView?.isHidden = isEmpty

        for (index, entry) in entries.enumerated() {
            let row = makeAppShortcutRow(entry: entry, index: index, showSeparator: index + 1 < entries.count)
            row.chooseAppButton.isEnabled = enabled
            row.recorder.isEnabled = enabled
            row.removeButton.isEnabled = enabled
            appShortcutRows.append(row)
            appShortcutsRowsStack.addArrangedSubview(row.container)
            row.container.widthAnchor.constraint(equalTo: appShortcutsRowsStack.widthAnchor).isActive = true
        }

        let width = max(appShortcutsScrollView?.contentView.bounds.width ?? 0, 420)
        appShortcutsDocumentWidthConstraint?.constant = width
        appShortcutsRowsStack.needsLayout = true
        appShortcutsRowsStack.layoutSubtreeIfNeeded()
        if let scroll = appShortcutsScrollView {
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        appShortcutsAddButton.isEnabled = enabled && entries.count < ConfigStore.maxAppShortcuts
    }

    private func makeAppShortcutRow(
        entry: AppShortcutEntry,
        index: Int,
        showSeparator: Bool
    ) -> AppShortcutRowViews {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = appShortcutIcon(bundleID: entry.bundleID, size: 32)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let chooseApp = NSButton(
            title: appShortcutButtonTitle(bundleID: entry.bundleID),
            target: self,
            action: #selector(chooseAppShortcutApp(_:))
        )
        chooseApp.bezelStyle = .recessed
        chooseApp.isBordered = false
        chooseApp.alignment = .left
        chooseApp.lineBreakMode = .byTruncatingTail
        chooseApp.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        chooseApp.tag = index
        chooseApp.toolTip = "Choose a different app"
        chooseApp.translatesAutoresizingMaskIntoConstraints = false
        chooseApp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chooseApp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let recorder = ShortcutRecorderControl()
        recorder.mode = .letterOrDigitChord
        recorder.display(chord: entry.chord)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.setContentHuggingPriority(.required, for: .horizontal)
        recorder.setContentCompressionResistancePriority(.required, for: .horizontal)
        let capturedIndex = index
        recorder.onRecord = { [weak self] chord in
            self?.applyAppShortcutChord(chord, at: capturedIndex)
        }

        let remove = NSButton(title: "", target: self, action: #selector(removeAppShortcutRow(_:)))
        remove.bezelStyle = .inline
        remove.isBordered = false
        let trashConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove")?
            .withSymbolConfiguration(trashConfig)
        remove.imagePosition = .imageOnly
        remove.contentTintColor = .secondaryLabelColor
        remove.toolTip = "Remove"
        remove.tag = index
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.setContentHuggingPriority(.required, for: .horizontal)
        remove.setContentCompressionResistancePriority(.required, for: .horizontal)

        let conflict = SettingsWindowController.conflictLabel()
        conflict.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = !showSeparator

        container.addSubview(iconView)
        container.addSubview(chooseApp)
        container.addSubview(recorder)
        container.addSubview(remove)
        container.addSubview(conflict)
        container.addSubview(separator)

        // Three fixed columns: app (flex) | shortcut (108) | remove (24)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -1),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            chooseApp.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            chooseApp.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            chooseApp.trailingAnchor.constraint(lessThanOrEqualTo: recorder.leadingAnchor, constant: -12),

            remove.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            remove.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 24),
            remove.heightAnchor.constraint(equalToConstant: 24),

            recorder.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -8),
            recorder.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            recorder.widthAnchor.constraint(equalToConstant: 108),

            conflict.leadingAnchor.constraint(equalTo: chooseApp.leadingAnchor),
            conflict.trailingAnchor.constraint(lessThanOrEqualTo: recorder.leadingAnchor),
            conflict.topAnchor.constraint(equalTo: chooseApp.bottomAnchor, constant: 2),
            conflict.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),

            separator.leadingAnchor.constraint(equalTo: chooseApp.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return AppShortcutRowViews(
            container: container,
            iconView: iconView,
            chooseAppButton: chooseApp,
            recorder: recorder,
            removeButton: remove,
            conflictLabel: conflict,
            index: index
        )
    }

    private func appShortcutButtonTitle(bundleID: String) -> String {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Choose App…" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            return url.deletingPathExtension().lastPathComponent
        }
        return trimmed
    }

    private func appShortcutIcon(bundleID: String, size: CGFloat = 32) -> NSImage? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
        else {
            let placeholder = NSImage(
                systemSymbolName: "app.dashed",
                accessibilityDescription: "Choose app"
            )
            placeholder?.size = NSSize(width: size, height: size)
            return placeholder
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    /// Opens an application picker starting in `/Applications`. Returns the selected bundle ID.
    private func pickApplicationBundleID() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "Choose an application"
        panel.prompt = "Choose"
        panel.title = "Choose Application"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
            NSSound.beep()
            return nil
        }
        return bundleID
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

        appShortcutsEnabledSwitch.target = self
        appShortcutsEnabledSwitch.action = #selector(appShortcutsChanged)
        appShortcutsAddButton.target = self
        appShortcutsAddButton.action = #selector(addAppShortcut)
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
            proposed: proposed,
            additionalConflicts: config.appShortcuts.entries.map(\.chord)
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
            proposed: proposed,
            additionalConflicts: config.appShortcuts.entries.map(\.chord)
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

    @objc private func appShortcutsChanged() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        config.appShortcuts.enabled = appShortcutsEnabledSwitch.state == .on
        menuBar.apply(config, write: true)
        setEnabled(config.appShortcuts.enabled, controls: appShortcutsDependentControls)
        appShortcutsAddButton.isEnabled = config.appShortcuts.enabled
            && config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts
        for row in appShortcutRows {
            row.chooseAppButton.isEnabled = config.appShortcuts.enabled
            row.recorder.isEnabled = config.appShortcuts.enabled
            row.removeButton.isEnabled = config.appShortcuts.enabled
        }
    }

    @objc private func addAppShortcut() {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        guard config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts else {
            NSSound.beep()
            return
        }
        guard let bundleID = pickApplicationBundleID() else { return }
        guard let chord = nextFreeAppShortcutChord(config: config) else {
            NSSound.beep()
            return
        }
        config.appShortcuts.entries.append(AppShortcutEntry(bundleID: bundleID, chord: chord))
        menuBar.apply(config, write: true)
        rebuildAppShortcutRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: appShortcutsDependentControls)
    }

    @objc private func chooseAppShortcutApp(_ sender: NSButton) {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        let index = sender.tag
        guard config.appShortcuts.entries.indices.contains(index) else { return }
        guard let bundleID = pickApplicationBundleID() else { return }
        config.appShortcuts.entries[index].bundleID = bundleID
        menuBar.apply(config, write: true)
        sender.title = appShortcutButtonTitle(bundleID: bundleID)
        if let row = appShortcutRows.first(where: { $0.index == index }) {
            row.iconView.image = appShortcutIcon(bundleID: bundleID, size: 32)
        }
    }

    @objc private func removeAppShortcutRow(_ sender: NSButton) {
        guard !suppressActions, let menuBar else { return }
        var config = menuBar.currentConfig
        let index = sender.tag
        guard config.appShortcuts.entries.indices.contains(index) else { return }
        config.appShortcuts.entries.remove(at: index)
        menuBar.apply(config, write: true)
        rebuildAppShortcutRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: appShortcutsDependentControls)
    }

    private func applyAppShortcutChord(_ proposed: KeyChord, at index: Int) {
        guard let menuBar else { return }
        var config = menuBar.currentConfig
        guard config.appShortcuts.entries.indices.contains(index) else { return }
        var conflicting = [
            config.windowManagement.maximize,
            config.windowManagement.equalSplit,
        ]
        for (i, entry) in config.appShortcuts.entries.enumerated() where i != index {
            conflicting.append(entry.chord)
        }
        let row = appShortcutRows.first { $0.index == index }
        switch validatedAppShortcutChord(
            proposed: proposed,
            conflicting: conflicting,
            desktopSwitch: config.desktop.switchModifiers,
            desktopMove: config.desktop.moveModifiers
        ) {
        case .accepted(let value):
            if let row { clearConflict(row.conflictLabel) }
            config.appShortcuts.entries[index].chord = value
            menuBar.apply(config, write: true)
        case .conflict:
            NSSound.beep()
            if let row { showConflict(row.conflictLabel) }
            row?.recorder.display(chord: config.appShortcuts.entries[index].chord)
        case .invalid:
            NSSound.beep()
            row?.recorder.display(chord: config.appShortcuts.entries[index].chord)
        }
    }

    /// Prefer Control+Option+Command + first free letter a…z.
    private func nextFreeAppShortcutChord(config: AppConfig) -> KeyChord? {
        let modifiers = ModifierFlags(alt: true, shift: false, ctrl: true, cmd: true)
        let taken = Set(
            [config.windowManagement.maximize, config.windowManagement.equalSplit]
                + config.appShortcuts.entries.map(\.chord)
        )
        for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
            let key = Character(UnicodeScalar(scalar)!)
            let chord = KeyChord(modifiers: modifiers, key: key)
            if !taken.contains(chord) {
                return chord
            }
        }
        return nil
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
