import AppKit
import UniformTypeIdentifiers

/// Settings UI for the App Shortcuts module (extracted to keep SettingsWindowController under file_length).
@MainActor
final class AppShortcutsSettingsPane {
    private final class RowViews {
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

    weak var menuBar: MenuBarController?
    /// When true, control actions no-op (Settings is syncing from config).
    var isSuppressing: () -> Bool = { false }

    private let enabledSwitch = NSSwitch()
    private let listBox = NSBox()
    private let rowsStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No shortcuts yet")
    private let addButton = NSButton(title: "Add Shortcut", target: nil, action: nil)
    private var rows: [RowViews] = []
    private var dependentControls: [NSView] = []
    private var scrollView: NSScrollView?
    private var documentWidthConstraint: NSLayoutConstraint?

    private(set) lazy var rootView: NSView = makeRootView()

    func display(_ config: AppConfig) {
        enabledSwitch.state = config.appShortcuts.enabled ? .on : .off
        rebuildRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: dependentControls)
        addButton.isEnabled = config.appShortcuts.enabled
            && config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts
    }

    func wireActions() {
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)
        addButton.target = self
        addButton.action = #selector(addEntry)
    }

    // MARK: - Build

    private func makeRootView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(labeledSwitchRow(title: "App Shortcuts module", switchControl: enabledSwitch))

        let help = NSTextField(
            labelWithString: "Jump to an app’s Space instantly. Already frontmost does nothing."
        )
        help.textColor = .secondaryLabelColor
        help.font = NSFont.systemFont(ofSize: 11)
        help.maximumNumberOfLines = 2
        help.preferredMaxLayoutWidth = 420
        stack.addArrangedSubview(help)

        listBox.boxType = .custom
        listBox.titlePosition = .noTitle
        listBox.cornerRadius = 10
        listBox.borderWidth = 1
        listBox.borderColor = .separatorColor
        listBox.fillColor = .controlBackgroundColor
        listBox.contentViewMargins = NSSize(width: 0, height: 0)
        listBox.translatesAutoresizingMaskIntoConstraints = false
        listBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        listBox.heightAnchor.constraint(equalToConstant: 248).isActive = true

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0
        rowsStack.detachesHiddenViews = true
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rowsStack
        scrollView = scroll

        let clip = scroll.contentView
        let widthConstraint = rowsStack.widthAnchor.constraint(equalToConstant: 420)
        documentWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: clip.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            widthConstraint,
        ])

        if let content = listBox.contentView {
            content.addSubview(scroll)
            content.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: content.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
                emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            ])
        }
        stack.addArrangedSubview(listBox)

        let addConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")?
            .withSymbolConfiguration(addConfig)
        {
            addButton.image = plus
            addButton.imagePosition = .imageLeading
        }
        addButton.bezelStyle = .rounded
        stack.addArrangedSubview(addButton)

        dependentControls = [help, listBox, addButton]
        return stack
    }

    private func rebuildRows(entries: [AppShortcutEntry]) {
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll()

        let enabled = enabledSwitch.state == .on
        let isEmpty = entries.isEmpty
        emptyLabel.isHidden = !isEmpty
        scrollView?.isHidden = isEmpty

        for (index, entry) in entries.enumerated() {
            let row = makeRow(entry: entry, index: index, showSeparator: index + 1 < entries.count)
            row.chooseAppButton.isEnabled = enabled
            row.recorder.isEnabled = enabled
            row.removeButton.isEnabled = enabled
            rows.append(row)
            rowsStack.addArrangedSubview(row.container)
            row.container.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let width = max(scrollView?.contentView.bounds.width ?? 0, 420)
        documentWidthConstraint?.constant = width
        rowsStack.needsLayout = true
        rowsStack.layoutSubtreeIfNeeded()
        if let scroll = scrollView {
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        addButton.isEnabled = enabled && entries.count < ConfigStore.maxAppShortcuts
    }

    private func makeRow(entry: AppShortcutEntry, index: Int, showSeparator: Bool) -> RowViews {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = appIcon(bundleID: entry.bundleID, size: 32)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let chooseApp = NSButton(
            title: appTitle(bundleID: entry.bundleID),
            target: self,
            action: #selector(chooseApp(_:))
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
            self?.applyChord(chord, at: capturedIndex)
        }

        let remove = NSButton(title: "", target: self, action: #selector(removeEntry(_:)))
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

        let conflict = Self.conflictLabel()
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

        return RowViews(
            container: container,
            iconView: iconView,
            chooseAppButton: chooseApp,
            recorder: recorder,
            removeButton: remove,
            conflictLabel: conflict,
            index: index
        )
    }

    // MARK: - Actions

    @objc private func enabledChanged() {
        guard !isSuppressing(), let menuBar else { return }
        var config = menuBar.currentConfig
        config.appShortcuts.enabled = enabledSwitch.state == .on
        menuBar.apply(config, write: true)
        setEnabled(config.appShortcuts.enabled, controls: dependentControls)
        addButton.isEnabled = config.appShortcuts.enabled
            && config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts
        for row in rows {
            row.chooseAppButton.isEnabled = config.appShortcuts.enabled
            row.recorder.isEnabled = config.appShortcuts.enabled
            row.removeButton.isEnabled = config.appShortcuts.enabled
        }
    }

    @objc private func addEntry() {
        guard !isSuppressing(), let menuBar else { return }
        var config = menuBar.currentConfig
        guard config.appShortcuts.entries.count < ConfigStore.maxAppShortcuts else {
            NSSound.beep()
            return
        }
        guard let bundleID = pickApplicationBundleID() else { return }
        guard let chord = nextFreeChord(config: config) else {
            NSSound.beep()
            return
        }
        config.appShortcuts.entries.append(AppShortcutEntry(bundleID: bundleID, chord: chord))
        menuBar.apply(config, write: true)
        rebuildRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: dependentControls)
    }

    @objc private func chooseApp(_ sender: NSButton) {
        guard !isSuppressing(), let menuBar else { return }
        var config = menuBar.currentConfig
        let index = sender.tag
        guard config.appShortcuts.entries.indices.contains(index) else { return }
        guard let bundleID = pickApplicationBundleID() else { return }
        config.appShortcuts.entries[index].bundleID = bundleID
        menuBar.apply(config, write: true)
        sender.title = appTitle(bundleID: bundleID)
        if let row = rows.first(where: { $0.index == index }) {
            row.iconView.image = appIcon(bundleID: bundleID, size: 32)
        }
    }

    @objc private func removeEntry(_ sender: NSButton) {
        guard !isSuppressing(), let menuBar else { return }
        var config = menuBar.currentConfig
        let index = sender.tag
        guard config.appShortcuts.entries.indices.contains(index) else { return }
        config.appShortcuts.entries.remove(at: index)
        menuBar.apply(config, write: true)
        rebuildRows(entries: config.appShortcuts.entries)
        setEnabled(config.appShortcuts.enabled, controls: dependentControls)
    }

    private func applyChord(_ proposed: KeyChord, at index: Int) {
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
        let row = rows.first { $0.index == index }
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

    // MARK: - Helpers

    private func appTitle(bundleID: String) -> String {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Choose App…" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            return url.deletingPathExtension().lastPathComponent
        }
        return trimmed
    }

    private func appIcon(bundleID: String, size: CGFloat = 32) -> NSImage? {
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

    private func nextFreeChord(config: AppConfig) -> KeyChord? {
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

    private func labeledSwitchRow(title: String, switchControl: NSSwitch) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.distribution = .fill
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        switchControl.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(switchControl)
        return row
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
}
