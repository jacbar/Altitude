import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "Config")

/// Log label used instead of absolute paths so the username never hits the system log.
private let configPathLogLabel = "~/.config/altitude/config.toml"

struct DesktopConfig: Equatable, Sendable {
    var enabled: Bool
    var disableMotion: Bool
    var maxSpace: Int
    var switchModifiers: ModifierFlags
    var moveModifiers: ModifierFlags

    static let `default` = DesktopConfig(
        enabled: true,
        disableMotion: false,
        maxSpace: 9,
        switchModifiers: .optionOnly,
        moveModifiers: .optionShift
    )
}

struct CommandTabConfig: Equatable, Sendable {
    var enabled: Bool
    var disableMotion: Bool

    static let `default` = CommandTabConfig(enabled: false, disableMotion: false)
}

struct WindowManagementConfig: Equatable, Sendable {
    var enabled: Bool
    var margin: Int
    var maximize: KeyChord
    var equalSplit: KeyChord

    static let `default` = WindowManagementConfig(
        enabled: true,
        margin: 8,
        maximize: .maximizeDefault,
        equalSplit: .equalSplitDefault
    )
}

struct AppConfig: Equatable, Sendable {
    var version: Int
    var launchAtLogin: Bool
    var desktop: DesktopConfig
    var commandTab: CommandTabConfig
    var windowManagement: WindowManagementConfig

    static let `default` = AppConfig(
        version: 2,
        launchAtLogin: false,
        desktop: .default,
        commandTab: .default,
        windowManagement: .default
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
        load(from: configFileURL)
    }

    static func load(from url: URL) -> AppConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            log.info("No config at \(configPathLogLabel, privacy: .public); using defaults")
            return .default
        }

        do {
            try validateConfigURL(url)
            let resolved = url.resolvingSymlinksInPath()
            try validateConfigURL(resolved)

            let handle = try FileHandle(forReadingFrom: resolved)
            defer { try? handle.close() }

            let limit = Int(maxConfigBytes) + 1
            let data = try handle.read(upToCount: limit) ?? Data()
            if UInt64(data.count) > maxConfigBytes {
                log.error(
                    "Config at \(configPathLogLabel, privacy: .public) exceeds \(maxConfigBytes) bytes; using defaults"
                )
                return .default
            }
            guard let text = String(data: data, encoding: .utf8) else {
                log.error("Failed to load config: not valid UTF-8; using defaults")
                return .default
            }
            let config = MinimalTOML.parseAltitudeConfig(text)
            log.info("Loaded config version \(config.version) from \(configPathLogLabel, privacy: .public)")
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
            log.info("Wrote starter config to \(configPathLogLabel, privacy: .public)")
        } catch {
            log.error("Could not write starter config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deterministically rewrites known keys (used by menu toggles). Does not preserve comments.
    static func save(_ config: AppConfig) throws {
        try save(config, to: configFileURL)
    }

    static func save(_ config: AppConfig, to url: URL) throws {
        try validateConfigURL(url, allowMissing: true)
        let text = render(config)
        let fm = FileManager.default

        let writeURL: URL
        if fm.fileExists(atPath: url.path) {
            let resolved = url.resolvingSymlinksInPath()
            try validateConfigURL(resolved)
            writeURL = resolved
        } else {
            writeURL = url
        }

        try fm.createDirectory(
            at: writeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: writeURL, atomically: true, encoding: .utf8)
        log.info("Wrote config to \(configPathLogLabel, privacy: .public)")
    }

    /// Canonical TOML text for `AppConfig`. Shared by save and round-trip tests.
    static func render(_ config: AppConfig) -> String {
        let d = config.desktop
        let c = config.commandTab
        let w = config.windowManagement
        return """
        version = \(config.version)

        [app]
        launch_at_login = \(tomlBool(config.launchAtLogin))

        [desktop]
        enabled = \(tomlBool(d.enabled))
        disable_motion = \(tomlBool(d.disableMotion))
        max_space = \(d.maxSpace)

        [desktop.switch]
        alt = \(tomlBool(d.switchModifiers.alt))
        shift = \(tomlBool(d.switchModifiers.shift))
        ctrl = \(tomlBool(d.switchModifiers.ctrl))
        cmd = \(tomlBool(d.switchModifiers.cmd))

        [desktop.move]
        alt = \(tomlBool(d.moveModifiers.alt))
        shift = \(tomlBool(d.moveModifiers.shift))
        ctrl = \(tomlBool(d.moveModifiers.ctrl))
        cmd = \(tomlBool(d.moveModifiers.cmd))

        [command_tab]
        enabled = \(tomlBool(c.enabled))
        disable_motion = \(tomlBool(c.disableMotion))

        [window_management]
        enabled = \(tomlBool(w.enabled))
        margin = \(w.margin)

        [window_management.maximize]
        alt = \(tomlBool(w.maximize.modifiers.alt))
        shift = \(tomlBool(w.maximize.modifiers.shift))
        ctrl = \(tomlBool(w.maximize.modifiers.ctrl))
        cmd = \(tomlBool(w.maximize.modifiers.cmd))
        key = \(w.maximize.key)

        [window_management.equal_split]
        alt = \(tomlBool(w.equalSplit.modifiers.alt))
        shift = \(tomlBool(w.equalSplit.modifiers.shift))
        ctrl = \(tomlBool(w.equalSplit.modifiers.ctrl))
        cmd = \(tomlBool(w.equalSplit.modifiers.cmd))
        key = \(w.equalSplit.key)
        """
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
            log.error("Refusing config outside home")
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

        var switchPartial = PartialModifierFlags()
        var movePartial = PartialModifierFlags()
        var maximizePartial = PartialKeyChord(modifiers: PartialModifierFlags(), key: nil)
        var equalSplitPartial = PartialKeyChord(modifiers: PartialModifierFlags(), key: nil)

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            // `#` starts a comment even mid-value; values are not quoted strings.
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

            // Old schema sections are ignored entirely (no migration).
            if let section, ["spaces", "hotkeys", "arrange"].contains(section) {
                continue
            }

            switch (section, key) {
            case (nil, "version"), ("", "version"):
                if let int = Int(value) { config.version = int } else { warnInvalid(qualifiedKey, value) }

            case ("app", "launch_at_login"):
                if let bool = parseBool(value) { config.launchAtLogin = bool } else { warnInvalid(qualifiedKey, value) }

            case ("desktop", "enabled"):
                if let bool = parseBool(value) { config.desktop.enabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("desktop", "disable_motion"):
                if let bool = parseBool(value) { config.desktop.disableMotion = bool } else { warnInvalid(qualifiedKey, value) }
            case ("desktop", "max_space"):
                if let int = Int(value) {
                    config.desktop.maxSpace = max(1, min(int, ConfigStore.maxHotkeySpace))
                } else {
                    warnInvalid(qualifiedKey, value)
                }

            case ("desktop.switch", "alt"):
                assignModifier(&switchPartial.alt, value, qualifiedKey)
            case ("desktop.switch", "shift"):
                assignModifier(&switchPartial.shift, value, qualifiedKey)
            case ("desktop.switch", "ctrl"):
                assignModifier(&switchPartial.ctrl, value, qualifiedKey)
            case ("desktop.switch", "cmd"):
                assignModifier(&switchPartial.cmd, value, qualifiedKey)

            case ("desktop.move", "alt"):
                assignModifier(&movePartial.alt, value, qualifiedKey)
            case ("desktop.move", "shift"):
                assignModifier(&movePartial.shift, value, qualifiedKey)
            case ("desktop.move", "ctrl"):
                assignModifier(&movePartial.ctrl, value, qualifiedKey)
            case ("desktop.move", "cmd"):
                assignModifier(&movePartial.cmd, value, qualifiedKey)

            case ("command_tab", "enabled"):
                if let bool = parseBool(value) { config.commandTab.enabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("command_tab", "disable_motion"):
                if let bool = parseBool(value) { config.commandTab.disableMotion = bool } else { warnInvalid(qualifiedKey, value) }

            case ("window_management", "enabled"):
                if let bool = parseBool(value) { config.windowManagement.enabled = bool } else { warnInvalid(qualifiedKey, value) }
            case ("window_management", "margin"):
                if let int = Int(value) {
                    config.windowManagement.margin = max(0, min(int, 256))
                } else {
                    warnInvalid(qualifiedKey, value)
                }

            case ("window_management.maximize", "alt"):
                assignModifier(&maximizePartial.modifiers.alt, value, qualifiedKey)
            case ("window_management.maximize", "shift"):
                assignModifier(&maximizePartial.modifiers.shift, value, qualifiedKey)
            case ("window_management.maximize", "ctrl"):
                assignModifier(&maximizePartial.modifiers.ctrl, value, qualifiedKey)
            case ("window_management.maximize", "cmd"):
                assignModifier(&maximizePartial.modifiers.cmd, value, qualifiedKey)
            case ("window_management.maximize", "key"):
                if let letter = parseKeyLetter(value) {
                    maximizePartial.key = letter
                } else {
                    warnInvalid(qualifiedKey, value)
                    maximizePartial.key = nil
                }

            case ("window_management.equal_split", "alt"):
                assignModifier(&equalSplitPartial.modifiers.alt, value, qualifiedKey)
            case ("window_management.equal_split", "shift"):
                assignModifier(&equalSplitPartial.modifiers.shift, value, qualifiedKey)
            case ("window_management.equal_split", "ctrl"):
                assignModifier(&equalSplitPartial.modifiers.ctrl, value, qualifiedKey)
            case ("window_management.equal_split", "cmd"):
                assignModifier(&equalSplitPartial.modifiers.cmd, value, qualifiedKey)
            case ("window_management.equal_split", "key"):
                if let letter = parseKeyLetter(value) {
                    equalSplitPartial.key = letter
                } else {
                    warnInvalid(qualifiedKey, value)
                    equalSplitPartial.key = nil
                }

            default:
                log.warning("Ignoring unknown config key \(qualifiedKey, privacy: .public)")
            }
        }

        let desktopResolved = resolveDesktopShortcuts(switch: switchPartial, move: movePartial)
        if desktopResolved.usedFallback {
            log.warning("Desktop switch/move shortcuts were empty or identical; using Option and Option+Shift defaults")
        }
        config.desktop.switchModifiers = desktopResolved.switchModifiers
        config.desktop.moveModifiers = desktopResolved.moveModifiers

        let windowResolved = resolveWindowChords(maximize: maximizePartial, equalSplit: equalSplitPartial)
        if windowResolved.usedFallback {
            log.warning("Window management chords were identical; using Control+Option+F and Control+Option+A defaults")
        }
        config.windowManagement.maximize = windowResolved.maximize
        config.windowManagement.equalSplit = windowResolved.equalSplit

        return config
    }

    private static func assignModifier(_ target: inout Bool?, _ value: String, _ qualifiedKey: String) {
        if let bool = parseBool(value) {
            target = bool
        } else {
            warnInvalid(qualifiedKey, value)
        }
    }

    /// Unquoted single a–z letter (case-insensitive). Quoted values are invalid.
    private static func parseKeyLetter(_ value: String) -> Character? {
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            return nil
        }
        guard value.count == 1, let c = value.lowercased().first, ("a"..."z").contains(c) else {
            return nil
        }
        return c
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
