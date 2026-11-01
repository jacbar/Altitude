import Foundation

/// Pure config apply / launch-at-login decisions (no AppKit).
enum ConfigApply {
    /// Enabled or approval-pending toggles off; otherwise on.
    static func toggledDesired(isEnabled: Bool, requiresApproval: Bool) -> Bool {
        if isEnabled || requiresApproval {
            return false
        }
        return true
    }

    /// Applies Launch at Login via `setEnabled`, then persists. Rolls the service back if save fails.
    static func setLaunchAtLogin(
        desired: Bool,
        config: AppConfig,
        setEnabled: (Bool) throws -> Void,
        save: (AppConfig) throws -> Void
    ) -> AppConfig {
        let previous = config.launchAtLogin
        do {
            try setEnabled(desired)
        } catch {
            return config
        }

        var updated = config
        updated.launchAtLogin = desired
        do {
            try save(updated)
            return updated
        } catch {
            do {
                try setEnabled(previous)
            } catch {
                // Caller surfaces failure; keep previous config either way.
            }
            return config
        }
    }

    /// Persists `updated`; on save failure returns `previous`.
    static func saving(
        previous: AppConfig,
        updated: AppConfig,
        save: (AppConfig) throws -> Void
    ) -> AppConfig {
        do {
            try save(updated)
            return updated
        } catch {
            return previous
        }
    }
}
