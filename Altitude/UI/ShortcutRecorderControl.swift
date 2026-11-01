import AppKit

/// Button that displays a shortcut and records the next press.
final class ShortcutRecorderControl: NSButton {
    enum Mode {
        /// Windows chords: modifiers + letter (a–z).
        case letterChord
        /// Desktop switch/move: modifiers only (⌥, ⌥⇧, …).
        case modifiersOnly
    }

    var mode: Mode = .letterChord {
        didSet { refreshTitle() }
    }

    var modifiers: ModifierFlags = .optionOnly {
        didSet { refreshTitle() }
    }

    var key: Character = "f" {
        didSet { refreshTitle() }
    }

    /// Letter-chord recording (Windows).
    var onRecord: ((KeyChord) -> Void)?

    /// Modifiers-only recording (Desktop).
    var onRecordModifiers: ((ModifierFlags) -> Void)?

    private var isRecording = false
    private var monitor: Any?
    private var pendingModifiers: ModifierFlags?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    func display(chord: KeyChord) {
        cancelRecording()
        modifiers = chord.modifiers
        key = chord.key
    }

    func display(modifiers: ModifierFlags) {
        cancelRecording()
        self.modifiers = modifiers
    }

    private func refreshTitle() {
        if isRecording {
            title = "Type shortcut"
        } else {
            switch mode {
            case .letterChord:
                title = shortcutSymbols(modifiers: modifiers, key: key)
            case .modifiersOnly:
                title = shortcutSymbols(modifiers: modifiers, key: nil)
            }
        }
    }

    @objc private func clicked() {
        if isRecording {
            cancelRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        isRecording = true
        pendingModifiers = nil
        refreshTitle()
        stopMonitoring()

        switch mode {
        case .letterChord:
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleLetterKey(event)
                return nil
            }
        case .modifiersOnly:
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.handleModifiersEvent(event)
                return nil
            }
        }
    }

    private func cancelRecording() {
        isRecording = false
        pendingModifiers = nil
        stopMonitoring()
        refreshTitle()
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleLetterKey(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelRecording()
            return
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard chars.count == 1, let letter = chars.first, ("a"..."z").contains(letter) else {
            NSSound.beep()
            return
        }

        let proposed = modifiersFromEvent(event)
        guard proposed.hasAny else {
            NSSound.beep()
            return
        }

        isRecording = false
        stopMonitoring()
        onRecord?(KeyChord(modifiers: proposed, key: letter))
    }

    private func handleModifiersEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                cancelRecording()
            }
            return
        }

        guard event.type == .flagsChanged else { return }

        let proposed = modifiersFromEvent(event)
        if proposed.hasAny {
            // Union while keys are held so releasing ⌥⇧ one-at-a-time still
            // records the full chord instead of collapsing to the last key.
            pendingModifiers = union(pendingModifiers ?? proposed, proposed)
            return
        }

        guard let pending = pendingModifiers, pending.hasAny else { return }

        isRecording = false
        pendingModifiers = nil
        stopMonitoring()
        onRecordModifiers?(pending)
    }

    private func modifiersFromEvent(_ event: NSEvent) -> ModifierFlags {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return ModifierFlags(
            alt: flags.contains(.option),
            shift: flags.contains(.shift),
            ctrl: flags.contains(.control),
            cmd: flags.contains(.command)
        )
    }

    private func union(_ a: ModifierFlags, _ b: ModifierFlags) -> ModifierFlags {
        ModifierFlags(
            alt: a.alt || b.alt,
            shift: a.shift || b.shift,
            ctrl: a.ctrl || b.ctrl,
            cmd: a.cmd || b.cmd
        )
    }
}
