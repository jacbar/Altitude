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

/// Weak box so Carbon callbacks no-op after the registrar is released.
private final class HotkeyCallbackContext {
    weak var registrar: HotkeyRegistrar?
}

/// Registers global Option / Option+Shift + digit hotkeys via Carbon.
final class HotkeyRegistrar {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var actionByID: [UInt32: HotkeyAction] = [:]
    private var applied: (config: AppConfig, maxN: Int)?
    private let onAction: (HotkeyAction) -> Void
    private let callbackContext = HotkeyCallbackContext()

    init(onAction: @escaping (HotkeyAction) -> Void) {
        self.onAction = onAction
        callbackContext.registrar = self
    }

    deinit {
        tearDownHandler()
    }

    func apply(config: AppConfig, spaceCount: Int) {
        let maxN = effectiveMaxHotkeySpace(maxSpace: config.maxSpace, spaceCount: spaceCount)
        if let applied, applied.config == config, applied.maxN == maxN {
            return
        }

        unregisterHotKeys()
        applied = (config, maxN)
        installHandlerIfNeeded()

        let digitKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]

        for n in 1...maxN {
            let keyCode = digitKeyCodes[n - 1]
            if config.switchEnabled {
                register(keyCode: keyCode, modifiers: UInt32(optionKey), id: UInt32(n), action: .switchTo(n))
            }
            if config.moveEnabled {
                register(
                    keyCode: keyCode,
                    modifiers: UInt32(optionKey | shiftKey),
                    id: UInt32(100 + n),
                    action: .moveTo(n)
                )
            }
        }

        if config.arrangeMaximizeEnabled {
            register(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: UInt32(controlKey | optionKey),
                id: 200,
                action: .maximizeAll
            )
        }
        if config.arrangeColumnsEnabled {
            register(
                keyCode: UInt32(kVK_ANSI_A),
                modifiers: UInt32(controlKey | optionKey),
                id: 201,
                action: .tileColumns
            )
        }

        log.info("Registered hotkeys for desktops 1...\(maxN)")
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: HotkeyAction) {
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
        } else {
            log.error("RegisterEventHotKey failed for id \(id): \(status)")
        }
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

        DispatchQueue.main.async { [onAction] in
            onAction(action)
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
