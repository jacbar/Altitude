import AppKit
import Carbon

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
    private var pollTimer: Timer?

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
            if mode == .modifiersOnly, let pending = pendingModifiers, pending.hasAny {
                title = shortcutSymbols(modifiers: pending, key: nil)
            } else {
                title = "Type shortcut"
            }
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
            // Pass flagsChanged through so AppKit keeps modifier state coherent;
            // also poll NSEvent.modifierFlags so multi-modifier chords still
            // register if individual flagsChanged events are coalesced/missed.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    if event.keyCode == UInt16(kVK_Escape) {
                        self.cancelRecording()
                        return nil
                    }
                    return nil
                }
                self.captureModifiers(Self.modifiers(from: event.modifierFlags))
                return event
            }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.pollModifierFlags()
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private func cancelRecording() {
        isRecording = false
        pendingModifiers = nil
        stopMonitoring()
        refreshTitle()
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleLetterKey(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard chars.count == 1, let letter = chars.first, ("a"..."z").contains(letter) else {
            NSSound.beep()
            return
        }

        let proposed = Self.modifiers(from: event.modifierFlags)
        guard proposed.hasAny else {
            NSSound.beep()
            return
        }

        isRecording = false
        stopMonitoring()
        onRecord?(KeyChord(modifiers: proposed, key: letter))
    }

    private func pollModifierFlags() {
        guard isRecording, mode == .modifiersOnly else { return }
        captureModifiers(Self.modifiers(from: NSEvent.modifierFlags))
    }

    private func captureModifiers(_ proposed: ModifierFlags) {
        guard isRecording, mode == .modifiersOnly else { return }

        if proposed.hasAny {
            pendingModifiers = Self.union(pendingModifiers ?? proposed, proposed)
            refreshTitle()
            return
        }

        guard let pending = pendingModifiers, pending.hasAny else { return }

        isRecording = false
        pendingModifiers = nil
        stopMonitoring()
        refreshTitle()
        onRecordModifiers?(pending)
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> ModifierFlags {
        let masked = flags.intersection([.option, .shift, .control, .command])
        return ModifierFlags(
            alt: masked.contains(.option),
            shift: masked.contains(.shift),
            ctrl: masked.contains(.control),
            cmd: masked.contains(.command)
        )
    }

    private static func union(_ a: ModifierFlags, _ b: ModifierFlags) -> ModifierFlags {
        ModifierFlags(
            alt: a.alt || b.alt,
            shift: a.shift || b.shift,
            ctrl: a.ctrl || b.ctrl,
            cmd: a.cmd || b.cmd
        )
    }
}
