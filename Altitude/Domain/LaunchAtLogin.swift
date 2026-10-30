import Foundation
import os.log
import ServiceManagement

private let log = Logger(subsystem: "com.altitude.app", category: "LaunchAtLogin")

enum LaunchAtLogin {
    /// True only when the login item is fully enabled (not pending approval).
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is waiting for the user to approve the login item in System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Value to write when the user clicks the menu item.
    /// A pending approval is cancelled so the click does not call `register()` again.
    static var toggledDesired: Bool {
        if isEnabled || requiresApproval {
            return false
        }
        return true
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
            log.info("Registered login item (status=\(String(describing: service.status), privacy: .public))")
        } else {
            try service.unregister()
            log.info("Unregistered login item (status=\(String(describing: service.status), privacy: .public))")
        }
    }

    /// Brings SMAppService in line with the desired config value. Logs and swallows failures.
    /// Enabled and approval-pending both count as registered: pending stays while desired is true,
    /// and is unregistered when desired is false.
    static func apply(desired: Bool) {
        let registered = isEnabled || requiresApproval
        guard registered != desired else { return }
        do {
            try setEnabled(desired)
        } catch {
            log.error(
                "Failed to reconcile launch-at-login to \(desired, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
