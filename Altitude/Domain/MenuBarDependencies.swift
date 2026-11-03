import Foundation

/// Load / save of `config.toml` for MenuBarController seams.
protocol ConfigPersisting {
    func load() -> ConfigLoadResult
    func save(_ config: AppConfig) throws
    func resolvedModificationDate() -> Date?
}

extension ConfigStore: ConfigPersisting {}

/// Login-item status and mutations used by the menu bar.
protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    @discardableResult
    func apply(desired: Bool) -> Bool
}

/// Production login-item backend (`SMAppService`).
struct SystemLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled: Bool { LaunchAtLogin.isEnabled }
    var requiresApproval: Bool { LaunchAtLogin.requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        try LaunchAtLogin.setEnabled(enabled)
    }

    @discardableResult
    func apply(desired: Bool) -> Bool {
        LaunchAtLogin.apply(desired: desired)
    }
}

/// Accessibility trust / prompt used by the menu bar.
protocol AccessibilityTrusting: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    @discardableResult
    func promptForAccessibilityIfNeeded() -> Bool
}

extension FocusedWindowResolver: AccessibilityTrusting {}

/// Whether a Settings / menu save may proceed against the on-disk config.
enum ConfigSaveGuard: Equatable {
    /// Disk matches the last successful load (or both are absent); write may proceed.
    case proceed
    /// On-disk file appeared, disappeared, or changed since the last successful load.
    case reload
    /// A previous load failed; writes stay locked until a successful Reload.
    case blocked
}

/// Pure rollback decisions shared by MenuBarController and tests.
enum MenuBarMutation {
    /// Decides whether a Settings or menu save may write / change Launch at Login.
    static func configSaveGuard(
        loadFailed: Bool,
        recordedModifiedAt: Date?,
        currentModifiedAt: Date?
    ) -> ConfigSaveGuard {
        if loadFailed { return .blocked }
        switch (recordedModifiedAt, currentModifiedAt) {
        case (nil, nil):
            return .proceed
        case (nil, .some), (.some, nil):
            return .reload
        case let (recorded?, current?) where recorded != current:
            return .reload
        case (.some, .some):
            return .proceed
        }
    }

    enum LaunchAtLoginOutcome: Equatable {
        /// `setEnabled` threw; config must stay at `previous`.
        case serviceFailed
        /// Save threw after a successful `setEnabled`; login item restored to `previous`.
        case saveFailedRestored(previous: Bool)
        /// Login item and config both updated to `desired`.
        case succeeded(desired: Bool)
    }

    /// Sets the login item, then persists. On save failure, restores the previous login-item value.
    static func setLaunchAtLogin(
        desired: Bool,
        previous: Bool,
        setEnabled: (Bool) throws -> Void,
        save: () throws -> Void
    ) -> LaunchAtLoginOutcome {
        do {
            try setEnabled(desired)
        } catch {
            return .serviceFailed
        }
        do {
            try save()
            return .succeeded(desired: desired)
        } catch {
            try? setEnabled(previous)
            return .saveFailedRestored(previous: previous)
        }
    }

    enum ApplyWriteOutcome: Equatable {
        case saveFailed
        case succeeded
    }

    /// Persists when `write` is true. On failure the caller restores the previous config.
    static func applyWrite(write: Bool, save: () throws -> Void) -> ApplyWriteOutcome {
        guard write else { return .succeeded }
        do {
            try save()
            return .succeeded
        } catch {
            return .saveFailed
        }
    }
}
