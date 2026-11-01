import AppKit

/// Button that displays a chord and records the next letter-with-modifiers press.
final class ShortcutRecorderControl: NSButton {
    var modifiers: ModifierFlags = .optionOnly {
        didSet { refreshTitle() }
    }

    var key: Character = "f" {
        didSet { refreshTitle() }
    }

    var onRecord: ((KeyChord) -> Void)?

    private var isRecording = false
    private var monitor: Any?

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

    private func refreshTitle() {
        if isRecording {
            title = "Type shortcut"
        } else {
            title = shortcutSymbols(modifiers: modifiers, key: key)
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
        refreshTitle()
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func cancelRecording() {
        isRecording = false
        stopMonitoring()
        refreshTitle()
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelRecording()
            return
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard chars.count == 1, let letter = chars.first, ("a"..."z").contains(letter) else {
            NSSound.beep()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let proposed = ModifierFlags(
            alt: flags.contains(.option),
            shift: flags.contains(.shift),
            ctrl: flags.contains(.control),
            cmd: flags.contains(.command)
        )
        guard proposed.hasAny else {
            NSSound.beep()
            return
        }

        isRecording = false
        stopMonitoring()
        onRecord?(KeyChord(modifiers: proposed, key: letter))
    }
}
