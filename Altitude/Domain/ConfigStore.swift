import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "Config")

struct AppConfig: Equatable, Sendable {
    var version: Int
    var launchAtLogin: Bool
    var disableAnimations: Bool
    /// Skip the slide for trackpad Space swipes, Control-Left/Right, and Command-Tab.
    var disableSystemMotions: Bool
    var switchEnabled: Bool
    var moveEnabled: Bool
    var maxSpace: Int
    /// Outer inset and inter-column gap for window arrangement (points).
    var arrangeMargin: Int
    var arrangeMaximizeEnabled: Bool
    var arrangeColumnsEnabled: Bool

    static let `default` = AppConfig(
        version: 1,
        launchAtLogin: false,
        disableAnimations: false,
        disableSystemMotions: false,
        switchEnabled: true,
        moveEnabled: true,
        maxSpace: 9,
        arrangeMargin: 8,
        arrangeMaximizeEnabled: true,
        arrangeColumnsEnabled: true
    )
}

enum ConfigStore {
    /// Hard cap matching Carbon digit hotkeys (1…9).
    static let maxHotkeySpace = 9
    /// Reject absurdly large config files (symlink / DoS guard).
    static let maxConfigBytes: UInt64 = 64 * 1024

    static var configDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/altitude", isDirectory: true)
    }

    static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    static func load() -> AppConfig {
        let url = configFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            log.info("No config at \(url.path, privacy: .public); using defaults")
            return .default
        }

        do {
            try validateConfigURL(url)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? UInt64, size > maxConfigBytes {
                log.error(
                    "Config at \(url.path, privacy: .public) is \(size) bytes (limit \(maxConfigBytes)); using defaults"
                )
                return .default
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let config = MinimalTOML.parseAltitudeConfig(text)
            log.info("Loaded config version \(config.version) from \(url.path, privacy: .public)")
            return config
        } catch {
            log.error("Failed to load config: \(error.localizedDescription, privacy: .public); using defaults")
            return .default
        }
    }

    /// Writes a starter config if none exists (does not overwrite stowed files).
    static func ensureExampleIfMissing() {
        let fm = FileManager.default
        let url = configFileURL
        guard !fm.fileExists(atPath: url.path) else { return }
        guard let template = Bundle.main.url(forResource: "config.example", withExtension: "toml") else {
            log.error("Bundled config.example.toml is missing; not writing a starter config")
            return
        }
        do {
            try fm.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            try fm.copyItem(at: template, to: url)
            log.info("Wrote starter config to \(url.path, privacy: .public)")
        } catch {
            log.error("Could not write starter config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deterministically rewrites known keys (used by menu toggles). Does not preserve comments.
    static func save(_ config: AppConfig) throws {
        try validateConfigURL(configFileURL, allowMissing: true)
        let text = """
        version = \(config.version)

        [app]
        launch_at_login = \(tomlBool(config.launchAtLogin))

        [spaces]
        disable_animations = \(tomlBool(config.disableAnimations))
        disable_system_motions = \(tomlBool(config.disableSystemMotions))

        [hotkeys]
        switch_enabled = \(tomlBool(config.switchEnabled))
        move_enabled = \(tomlBool(config.moveEnabled))
        max_space = \(config.maxSpace)

        [arrange]
        margin = \(config.arrangeMargin)
        maximize_enabled = \(tomlBool(config.arrangeMaximizeEnabled))
        columns_enabled = \(tomlBool(config.arrangeColumnsEnabled))
        """
        try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
        try text.write(to: configFileURL, atomically: true, encoding: .utf8)
        log.info("Wrote config to \(configFileURL.path, privacy: .public)")
    }

    private static func tomlBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Allows Stow-style symlinks when the resolved target stays under the user's home.
    private static func validateConfigURL(_ url: URL, allowMissing: Bool = false) throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
        if !fm.fileExists(atPath: url.path) {
            if allowMissing { return }
            throw CocoaError(.fileNoSuchFile)
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == home || resolved.hasPrefix(home + "/") else {
            log.error(
                "Refusing config outside home (resolved \(resolved, privacy: .public))"
            )
            throw CocoaError(.fileReadNoPermission)
        }
    }
}

/// Tiny TOML subset parser for Altitude's schema (avoids an SPM dependency in v1).
enum MinimalTOML {
    /// Invalid typed values keep the field default and are logged; unknown keys are ignored.
    static func parseAltitudeConfig(_ text: String) -> AppConfig {
        var config = AppConfig.default
        var section: String?

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            let qualifiedKey = section.map { "\($0).\(key)" } ?? key
            switch (section, key) {
            case (nil, "version"), ("", "version"):
                if let int = Int(value) { config.version = int } else { warnInvalid(qualifiedKey, value) }
            case ("app", "launch_at_login"):
                if let bool = parseBool(value) { config.launchAtLogin = bool } else { warnInvalid(qualifiedKey, value) }
            case ("spaces", "disable_animations"):
                if let bool = parseBool(value) { config.disableAnimations = bool } else { warnInvalid(qualifiedKey, value) }
            case ("spaces", "disable_system_motions"):
                if let bool = parseBool(value) { config.disableSystemMotions = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "switch_enabled"):
                if let bool = parseBool(value) { config.switchEnabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "move_enabled"):
                if let bool = parseBool(value) { config.moveEnabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "max_space"):
                if let int = Int(value) {
                    config.maxSpace = max(1, min(int, ConfigStore.maxHotkeySpace))
                } else {
                    warnInvalid(qualifiedKey, value)
                }
            case ("arrange", "margin"):
                if let int = Int(value) {
                    config.arrangeMargin = max(0, min(int, 256))
                } else {
                    warnInvalid(qualifiedKey, value)
                }
            case ("arrange", "maximize_enabled"):
                if let bool = parseBool(value) {
                    config.arrangeMaximizeEnabled = bool
                } else {
                    warnInvalid(qualifiedKey, value)
                }
            case ("arrange", "columns_enabled"):
                if let bool = parseBool(value) {
                    config.arrangeColumnsEnabled = bool
                } else {
                    warnInvalid(qualifiedKey, value)
                }
            default:
                log.warning("Ignoring unknown config key \(qualifiedKey, privacy: .public)")
            }
        }

        return config
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    private static func warnInvalid(_ key: String, _ value: String) {
        log.warning("Invalid value \(value, privacy: .public) for \(key, privacy: .public); keeping default")
    }
}
