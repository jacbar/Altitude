@preconcurrency import AppKit
import Carbon
import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "Hotkeys")

private let altitudeHotKeySignature: OSType = 0x414C5431 // 'ALT1'

enum HotkeyAction: Equatable {
    case switchTo(Int)
    case moveTo(Int)
    case maximizeAll
    case tileColumns
    case jumpToApp(Int)
}

/// One registered Carbon hotkey.
struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let id: UInt32
    let action: HotkeyAction
}

/// Weak box so Carbon callbacks no-op after the registrar is released.
private final class HotkeyCallbackContext: @unchecked Sendable {
    weak var registrar: HotkeyRegistrar?
}

/// Applies a set of Carbon hotkey bindings.
protocol HotkeyApplying: AnyObject {
    func apply(_ bindings: [HotkeyBinding])
}

/// Registers global hotkeys via Carbon.
final class HotkeyRegistrar: HotkeyApplying, @unchecked Sendable {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var actionByID: [UInt32: HotkeyAction] = [:]
    private var applied: [HotkeyBinding]?
    private let onAction: (HotkeyAction) -> Void
    private let callbackContext = HotkeyCallbackContext()

    init(onAction: @escaping (HotkeyAction) -> Void) {
        self.onAction = onAction
        callbackContext.registrar = self
    }

    deinit {
        tearDownHandler()
    }

    func apply(_ bindings: [HotkeyBinding]) {
        if applied == bindings {
            return
        }

        unregisterHotKeys()
        installHandlerIfNeeded()

        var succeededCount = 0
        for binding in bindings {
            if register(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                id: binding.id,
                action: binding.action
            ) {
                succeededCount += 1
            }
        }
        // Store the requested set so a partial Carbon failure does not thrash
        // unregister/re-register on every refresh. Failed keys stay unregistered.
        applied = bindings

        if succeededCount < bindings.count {
            log.error("Registered \(succeededCount)/\(bindings.count) hotkey(s); some RegisterEventHotKey calls failed")
        } else {
            log.info("Registered \(succeededCount) hotkey(s)")
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: HotkeyAction) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: altitudeHotKeySignature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
            actionByID[id] = action
            return true
        }
        log.error("RegisterEventHotKey failed for id \(id): \(status)")
        return false
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(callbackContext).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let context = Unmanaged<HotkeyCallbackContext>.fromOpaque(userData).takeUnretainedValue()
                guard let registrar = context.registrar else {
                    return OSStatus(eventNotHandledErr)
                }
                return registrar.handle(event: event)
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        if status != noErr {
            log.error("InstallEventHandler failed: \(status)")
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == altitudeHotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }
        guard let action = actionByID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        // Carbon delivers this callback on the main thread already.
        onAction(action)
        return noErr
    }

    private func unregisterHotKeys() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
    }

    private func tearDownHandler() {
        unregisterHotKeys()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        callbackContext.registrar = nil
    }
}

/// Resolves a lowercase letter to the virtual key code that types it on a keyboard layout.
protocol LetterKeyResolving {
    func keyCode(for letter: Character) -> UInt32?
}

/// Maps letters via the active input source layout (`UCKeyTranslate`), not a fixed US table.
struct LayoutLetterKeyResolver: LetterKeyResolving {
    func keyCode(for letter: Character) -> UInt32? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> UInt32? in
            guard let layoutPtr = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            let keyboardType = UInt32(LMGetKbdType())
            for virtualKey in 0..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var actualLength = 0
                let status = UCKeyTranslate(
                    layoutPtr,
                    UInt16(virtualKey),
                    UInt16(kUCKeyActionDisplay),
                    0,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &actualLength,
                    &chars
                )
                guard status == noErr, actualLength > 0,
                      let scalar = UnicodeScalar(chars[0]) else {
                    continue
                }
                let produced = Character(scalar)
                if produced.lowercased() == String(letter) {
                    return UInt32(virtualKey)
                }
            }
            return nil
        }
    }
}

enum HotkeyChordMapping {
    /// Carbon modifier mask from config flags.
    static func carbonModifiers(_ flags: ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.cmd { mask |= UInt32(cmdKey) }
        if flags.shift { mask |= UInt32(shiftKey) }
        if flags.alt { mask |= UInt32(optionKey) }
        if flags.ctrl { mask |= UInt32(controlKey) }
        return mask
    }

    static func digitKeyCode(_ n: Int) -> UInt32? {
        let codes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]
        guard (1...9).contains(n) else { return nil }
        return codes[n - 1]
    }

    /// Key code for digit character `0`…`9` (ANSI).
    static func digitCharacterKeyCode(_ key: Character) -> UInt32? {
        switch key {
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "0": return UInt32(kVK_ANSI_0)
        default: return nil
        }
    }

    /// Key code for a lowercase a–z letter on the active layout (via `resolver`).
    static func letterKeyCode(
        _ key: Character,
        resolver: LetterKeyResolving = LayoutLetterKeyResolver()
    ) -> UInt32? {
        guard ("a"..."z").contains(key) else { return nil }
        return resolver.keyCode(for: key)
    }

    /// Letter (layout) or digit (ANSI) key code for App Shortcuts / shared chords.
    static func chordKeyCode(
        _ key: Character,
        resolver: LetterKeyResolving = LayoutLetterKeyResolver()
    ) -> UInt32? {
        if ("a"..."z").contains(key) {
            return letterKeyCode(key, resolver: resolver)
        }
        return digitCharacterKeyCode(key)
    }
}
