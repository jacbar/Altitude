import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "Config")

struct AppConfig: Equatable, Sendable {
    var version: Int
    var disableAnimations: Bool
    /// Skip the slide for trackpad Space swipes, Control-Left/Right, and Command-Tab.
    var disableSystemMotions: Bool
    var switchEnabled: Bool
    var moveEnabled: Bool
    var maxSpace: Int

    static let `default` = AppConfig(
        version: 1,
        disableAnimations: false,
        disableSystemMotions: false,
        switchEnabled: true,
        moveEnabled: true,
        maxSpace: 9
    )
}

enum ConfigStore {
    static var configDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/altitude", isDirectory: true)
    }

    static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    static func load() -> AppConfig {
        let url = configFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.info("No config at \(url.path, privacy: .public); using defaults")
            return .default
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let config = try MinimalTOML.parseAltitudeConfig(text)
            log.info("Loaded config version \(config.version) from \(url.path, privacy: .public)")
            return config
        } catch {
            log.error("Failed to parse config: \(error.localizedDescription, privacy: .public); using defaults")
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
}

/// Tiny TOML subset parser for Altitude's schema (avoids an SPM dependency in v1).
enum MinimalTOML {
    enum ParseError: Error {
        case invalid
    }

    static func parseAltitudeConfig(_ text: String) throws -> AppConfig {
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
            case ("spaces", "disable_animations"):
                if let bool = parseBool(value) { config.disableAnimations = bool } else { warnInvalid(qualifiedKey, value) }
            case ("spaces", "disable_system_motions"):
                if let bool = parseBool(value) { config.disableSystemMotions = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "switch_enabled"):
                if let bool = parseBool(value) { config.switchEnabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "move_enabled"):
                if let bool = parseBool(value) { config.moveEnabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("hotkeys", "max_space"):
                if let int = Int(value) { config.maxSpace = max(1, min(int, 16)) } else { warnInvalid(qualifiedKey, value) }
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
