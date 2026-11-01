import AppKit
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
}

/// Stable Carbon hotkey ids for feature bindings.
enum HotkeyID {
    static func switchSpace(_ n: Int) -> UInt32 { UInt32(n) }
    static func moveSpace(_ n: Int) -> UInt32 { UInt32(100 + n) }
    static let maximize: UInt32 = 200
    static let tileColumns: UInt32 = 201
}

/// One registered Carbon hotkey.
struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let id: UInt32
    let action: HotkeyAction
}

/// Weak box so Carbon callbacks no-op after the registrar is released.
private final class HotkeyCallbackContext {
    weak var registrar: HotkeyRegistrar?
}

/// Registers global hotkeys via Carbon.
final class HotkeyRegistrar {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var actionByID: [UInt32: HotkeyAction] = [:]
    private var lastRequested: [HotkeyBinding]?
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

    /// Registers bindings, retrying previous failures. Returns bindings that failed to register.
    @discardableResult
    func apply(_ bindings: [HotkeyBinding]) -> [HotkeyBinding] {
        if lastRequested == bindings, let applied, applied == bindings {
            return []
        }

        unregisterHotKeys()
        lastRequested = bindings
        installHandlerIfNeeded()

        var succeeded: [HotkeyBinding] = []
        var failed: [HotkeyBinding] = []
        for binding in bindings {
            if register(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                id: binding.id,
                action: binding.action
            ) {
                succeeded.append(binding)
            } else {
                failed.append(binding)
            }
        }
        applied = succeeded
        log.info("Registered \(succeeded.count)/\(bindings.count) hotkey(s)")
        return failed
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

        if Thread.isMainThread {
            onAction(action)
        } else {
            DispatchQueue.main.async { [onAction] in
                onAction(action)
            }
        }
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

    private static let letterCodes: [Character: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
    ]

    /// ANSI letter key codes are layout-based, not alphabetical.
    static func letterKeyCode(_ key: Character) -> UInt32? {
        letterCodes[key]
    }
}
