import Foundation
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "Config")

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

struct ConfigStore {
    /// Hard cap matching Carbon digit hotkeys (1…9).
    static let maxHotkeySpace = 9
    /// Reject absurdly large config files (symlink / DoS guard). Measured on resolved bytes.
    static let maxConfigBytes: UInt64 = 64 * 1024

    /// Directory that contains `config.toml` (default: `~/.config/altitude`).
    let rootDirectory: URL
    /// Home boundary for symlink resolution checks (injectable so tests can use a temp tree).
    let homeDirectory: URL
    let fileManager: FileManager

    static var standard: ConfigStore { ConfigStore() }

    init(
        rootDirectory: URL? = nil,
        homeDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.homeDirectory = home
        self.rootDirectory = rootDirectory
            ?? home.appendingPathComponent(".config/altitude", isDirectory: true)
    }

    var configDirectoryURL: URL { rootDirectory }

    var configFileURL: URL {
        rootDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    // MARK: - Static convenience (MenuBarController / AppDelegate)

    static var configDirectoryURL: URL { standard.configDirectoryURL }
    static var configFileURL: URL { standard.configFileURL }

    static func load() -> AppConfig { standard.load() }

    static func save(_ config: AppConfig) throws { try standard.save(config) }

    static func ensureExampleIfMissing() { standard.ensureExampleIfMissing() }

    // MARK: - Instance API

    func load() -> AppConfig {
        let url = configFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            log.info("No config at \(url.path, privacy: .public); using defaults")
            return .default
        }

        do {
            try validateConfigURL(url)
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            try validateResolvedUnderHome(resolved)

            let handle = try FileHandle(forReadingFrom: resolved)
            defer { try? handle.close() }
            // Read one past the limit so oversized targets cannot bypass via symlink lstat size.
            let data = handle.readData(ofLength: Int(Self.maxConfigBytes) + 1)
            if data.count > Int(Self.maxConfigBytes) {
                log.error(
                    "Config at \(resolved.path, privacy: .public) exceeds \(Self.maxConfigBytes) bytes; using defaults"
                )
                return .default
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let config = MinimalTOML.parseAltitudeConfig(text)
            log.info("Loaded config version \(config.version) from \(url.path, privacy: .public)")
            return config
        } catch {
            log.error("Failed to load config: \(error.localizedDescription, privacy: .public); using defaults")
            return .default
        }
    }

    /// Writes a starter config if none exists (does not overwrite stowed files or dangling symlinks).
    func ensureExampleIfMissing() {
        let url = configFileURL
        if pathExistsIncludingBrokenSymlink(url) { return }
        guard let template = Bundle.main.url(forResource: "config.example", withExtension: "toml") else {
            log.error("Bundled config.example.toml is missing; not writing a starter config")
            return
        }
        do {
            try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: template, to: url)
            log.info("Wrote starter config to \(url.path, privacy: .public)")
        } catch {
            log.error("Could not write starter config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deterministically rewrites known keys (used by menu toggles). Does not preserve comments.
    func save(_ config: AppConfig) throws {
        let url = configFileURL
        let text = Self.renderConfig(config)
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        if isSymbolicLink(at: url) {
            // Dangling symlink: do not replace the link with a regular file.
            guard fileManager.fileExists(atPath: url.path) else {
                log.error("Refusing to save through dangling symlink at \(url.path, privacy: .public)")
                throw CocoaError(.fileNoSuchFile)
            }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            try validateResolvedUnderHome(resolved)
            try text.write(to: resolved, atomically: true, encoding: .utf8)
            log.info("Wrote config through symlink to \(resolved.path, privacy: .public)")
            return
        }

        try validateConfigURL(url, allowMissing: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        log.info("Wrote config to \(url.path, privacy: .public)")
    }

    /// Canonical TOML text written by `save` (also useful for parser round-trip tests).
    static func renderConfig(_ config: AppConfig) -> String {
        var lines: [String] = []
        var previousSection: String?
        var isFirst = true

        for entry in schema {
            if isFirst || previousSection != entry.section {
                if !isFirst {
                    lines.append("")
                }
                if let section = entry.section {
                    lines.append("[\(section)]")
                }
                previousSection = entry.section
                isFirst = false
            }
            lines.append("\(entry.key) = \(renderValue(config, field: entry.field))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderValue(_ config: AppConfig, field: ConfigField) -> String {
        let d = config.desktop
        let c = config.commandTab
        let w = config.windowManagement
        switch field {
        case .version: return String(config.version)
        case .launchAtLogin: return tomlBool(config.launchAtLogin)
        case .desktopEnabled: return tomlBool(d.enabled)
        case .desktopDisableMotion: return tomlBool(d.disableMotion)
        case .maxSpace: return String(d.maxSpace)
        case .switchAlt: return tomlBool(d.switchModifiers.alt)
        case .switchShift: return tomlBool(d.switchModifiers.shift)
        case .switchCtrl: return tomlBool(d.switchModifiers.ctrl)
        case .switchCmd: return tomlBool(d.switchModifiers.cmd)
        case .moveAlt: return tomlBool(d.moveModifiers.alt)
        case .moveShift: return tomlBool(d.moveModifiers.shift)
        case .moveCtrl: return tomlBool(d.moveModifiers.ctrl)
        case .moveCmd: return tomlBool(d.moveModifiers.cmd)
        case .commandTabEnabled: return tomlBool(c.enabled)
        case .commandTabDisableMotion: return tomlBool(c.disableMotion)
        case .windowEnabled: return tomlBool(w.enabled)
        case .margin: return String(w.margin)
        case .maximizeAlt: return tomlBool(w.maximize.modifiers.alt)
        case .maximizeShift: return tomlBool(w.maximize.modifiers.shift)
        case .maximizeCtrl: return tomlBool(w.maximize.modifiers.ctrl)
        case .maximizeCmd: return tomlBool(w.maximize.modifiers.cmd)
        case .maximizeKey: return String(w.maximize.key)
        case .equalSplitAlt: return tomlBool(w.equalSplit.modifiers.alt)
        case .equalSplitShift: return tomlBool(w.equalSplit.modifiers.shift)
        case .equalSplitCtrl: return tomlBool(w.equalSplit.modifiers.ctrl)
        case .equalSplitCmd: return tomlBool(w.equalSplit.modifiers.cmd)
        case .equalSplitKey: return String(w.equalSplit.key)
        }
    }

    private static func tomlBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Allows Stow-style symlinks when the resolved target stays under `homeDirectory`.
    private func validateConfigURL(_ url: URL, allowMissing: Bool = false) throws {
        if !fileManager.fileExists(atPath: url.path) {
            if allowMissing { return }
            throw CocoaError(.fileNoSuchFile)
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        try validateResolvedUnderHome(resolved)
    }

    private func validateResolvedUnderHome(_ resolved: URL) throws {
        let home = homeDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = resolved.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else {
            log.error(
                "Refusing config outside home (resolved \(path, privacy: .public))"
            )
            throw CocoaError(.fileReadNoPermission)
        }
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private func pathExistsIncludingBrokenSymlink(_ url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path) { return true }
        return isSymbolicLink(at: url)
    }
}

/// Shared ordered schema driving both `ConfigStore.renderConfig` and parsing.
private enum ConfigField {
    case version
    case launchAtLogin
    case desktopEnabled
    case desktopDisableMotion
    case maxSpace
    case switchAlt, switchShift, switchCtrl, switchCmd
    case moveAlt, moveShift, moveCtrl, moveCmd
    case commandTabEnabled
    case commandTabDisableMotion
    case windowEnabled
    case margin
    case maximizeAlt, maximizeShift, maximizeCtrl, maximizeCmd, maximizeKey
    case equalSplitAlt, equalSplitShift, equalSplitCtrl, equalSplitCmd, equalSplitKey
}

private struct ConfigSchemaEntry {
    let section: String?
    let key: String
    let field: ConfigField
}

private let schema: [ConfigSchemaEntry] = [
    .init(section: nil, key: "version", field: .version),
    .init(section: "app", key: "launch_at_login", field: .launchAtLogin),
    .init(section: "desktop", key: "enabled", field: .desktopEnabled),
    .init(section: "desktop", key: "disable_motion", field: .desktopDisableMotion),
    .init(section: "desktop", key: "max_space", field: .maxSpace),
    .init(section: "desktop.switch", key: "alt", field: .switchAlt),
    .init(section: "desktop.switch", key: "shift", field: .switchShift),
    .init(section: "desktop.switch", key: "ctrl", field: .switchCtrl),
    .init(section: "desktop.switch", key: "cmd", field: .switchCmd),
    .init(section: "desktop.move", key: "alt", field: .moveAlt),
    .init(section: "desktop.move", key: "shift", field: .moveShift),
    .init(section: "desktop.move", key: "ctrl", field: .moveCtrl),
    .init(section: "desktop.move", key: "cmd", field: .moveCmd),
    .init(section: "command_tab", key: "enabled", field: .commandTabEnabled),
    .init(section: "command_tab", key: "disable_motion", field: .commandTabDisableMotion),
    .init(section: "window_management", key: "enabled", field: .windowEnabled),
    .init(section: "window_management", key: "margin", field: .margin),
    .init(section: "window_management.maximize", key: "alt", field: .maximizeAlt),
    .init(section: "window_management.maximize", key: "shift", field: .maximizeShift),
    .init(section: "window_management.maximize", key: "ctrl", field: .maximizeCtrl),
    .init(section: "window_management.maximize", key: "cmd", field: .maximizeCmd),
    .init(section: "window_management.maximize", key: "key", field: .maximizeKey),
    .init(section: "window_management.equal_split", key: "alt", field: .equalSplitAlt),
    .init(section: "window_management.equal_split", key: "shift", field: .equalSplitShift),
    .init(section: "window_management.equal_split", key: "ctrl", field: .equalSplitCtrl),
    .init(section: "window_management.equal_split", key: "cmd", field: .equalSplitCmd),
    .init(section: "window_management.equal_split", key: "key", field: .equalSplitKey),
]

struct ConfigParseResult: Equatable {
    var config: AppConfig
    var ignoredKeys: [String]
}

/// Tiny TOML subset parser for Altitude's schema (avoids an SPM dependency in v1).
enum MinimalTOML {
    /// Invalid typed values keep the field default and are logged; unknown keys are ignored.
    static func parseAltitudeConfig(_ text: String) -> AppConfig {
        parseAltitudeConfigDetail(text).config
    }

    static func parseAltitudeConfigDetail(_ text: String) -> ConfigParseResult {
        var config = AppConfig.default
        var ignoredKeys: [String] = []
        var section: String?

        var switchPartial = PartialModifierFlags()
        var movePartial = PartialModifierFlags()
        var maximizePartial = PartialKeyChord(modifiers: PartialModifierFlags(), key: nil)
        var equalSplitPartial = PartialKeyChord(modifiers: PartialModifierFlags(), key: nil)

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

            // Old schema sections are ignored entirely (no migration).
            if let section, ["spaces", "hotkeys", "arrange"].contains(section) {
                continue
            }

            let normalizedSection: String? = (section == nil || section == "") ? nil : section
            guard let field = schemaField(section: normalizedSection, key: key) else {
                ignoredKeys.append(qualifiedKey)
                log.warning("Ignoring unknown config key \(qualifiedKey, privacy: .public)")
                continue
            }

            applyField(
                field,
                value: value,
                qualifiedKey: qualifiedKey,
                config: &config,
                switchPartial: &switchPartial,
                movePartial: &movePartial,
                maximizePartial: &maximizePartial,
                equalSplitPartial: &equalSplitPartial
            )
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

        return ConfigParseResult(config: config, ignoredKeys: ignoredKeys)
    }

    private static func schemaField(section: String?, key: String) -> ConfigField? {
        schema.first { $0.section == section && $0.key == key }?.field
    }

    private static func applyField(
        _ field: ConfigField,
        value: String,
        qualifiedKey: String,
        config: inout AppConfig,
        switchPartial: inout PartialModifierFlags,
        movePartial: inout PartialModifierFlags,
        maximizePartial: inout PartialKeyChord,
        equalSplitPartial: inout PartialKeyChord
    ) {
        switch field {
        case .version:
            if let int = Int(value) { config.version = int } else { warnInvalid(qualifiedKey, value) }
        case .launchAtLogin:
            if let bool = parseBool(value) { config.launchAtLogin = bool } else { warnInvalid(qualifiedKey, value) }
        case .desktopEnabled:
            if let bool = parseBool(value) { config.desktop.enabled = bool } else { warnInvalid(qualifiedKey, value) }
        case .desktopDisableMotion:
            if let bool = parseBool(value) { config.desktop.disableMotion = bool } else { warnInvalid(qualifiedKey, value) }
        case .maxSpace:
            if let int = Int(value) {
                config.desktop.maxSpace = max(1, min(int, ConfigStore.maxHotkeySpace))
            } else {
                warnInvalid(qualifiedKey, value)
            }
        case .switchAlt:
            assignModifier(&switchPartial.alt, value, qualifiedKey)
        case .switchShift:
            assignModifier(&switchPartial.shift, value, qualifiedKey)
        case .switchCtrl:
            assignModifier(&switchPartial.ctrl, value, qualifiedKey)
        case .switchCmd:
            assignModifier(&switchPartial.cmd, value, qualifiedKey)
        case .moveAlt:
            assignModifier(&movePartial.alt, value, qualifiedKey)
        case .moveShift:
            assignModifier(&movePartial.shift, value, qualifiedKey)
        case .moveCtrl:
            assignModifier(&movePartial.ctrl, value, qualifiedKey)
        case .moveCmd:
            assignModifier(&movePartial.cmd, value, qualifiedKey)
        case .commandTabEnabled:
            if let bool = parseBool(value) { config.commandTab.enabled = bool } else { warnInvalid(qualifiedKey, value) }
        case .commandTabDisableMotion:
            if let bool = parseBool(value) { config.commandTab.disableMotion = bool } else { warnInvalid(qualifiedKey, value) }
        case .windowEnabled:
            if let bool = parseBool(value) { config.windowManagement.enabled = bool } else { warnInvalid(qualifiedKey, value) }
        case .margin:
            if let int = Int(value) {
                config.windowManagement.margin = max(0, min(int, 256))
            } else {
                warnInvalid(qualifiedKey, value)
            }
        case .maximizeAlt:
            assignModifier(&maximizePartial.modifiers.alt, value, qualifiedKey)
        case .maximizeShift:
            assignModifier(&maximizePartial.modifiers.shift, value, qualifiedKey)
        case .maximizeCtrl:
            assignModifier(&maximizePartial.modifiers.ctrl, value, qualifiedKey)
        case .maximizeCmd:
            assignModifier(&maximizePartial.modifiers.cmd, value, qualifiedKey)
        case .maximizeKey:
            if let letter = parseKeyLetter(value) {
                maximizePartial.key = letter
            } else {
                warnInvalid(qualifiedKey, value)
                maximizePartial.key = nil
            }
        case .equalSplitAlt:
            assignModifier(&equalSplitPartial.modifiers.alt, value, qualifiedKey)
        case .equalSplitShift:
            assignModifier(&equalSplitPartial.modifiers.shift, value, qualifiedKey)
        case .equalSplitCtrl:
            assignModifier(&equalSplitPartial.modifiers.ctrl, value, qualifiedKey)
        case .equalSplitCmd:
            assignModifier(&equalSplitPartial.modifiers.cmd, value, qualifiedKey)
        case .equalSplitKey:
            if let letter = parseKeyLetter(value) {
                equalSplitPartial.key = letter
            } else {
                warnInvalid(qualifiedKey, value)
                equalSplitPartial.key = nil
            }
        }
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
