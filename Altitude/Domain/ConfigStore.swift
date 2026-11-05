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

struct AppShortcutEntry: Equatable, Sendable {
    var bundleID: String
    var chord: KeyChord
}

struct AppShortcutsConfig: Equatable, Sendable {
    var enabled: Bool
    var entries: [AppShortcutEntry]

    static let `default` = AppShortcutsConfig(enabled: false, entries: [])
}

struct AppConfig: Equatable, Sendable {
    var version: Int
    var launchAtLogin: Bool
    var desktop: DesktopConfig
    var commandTab: CommandTabConfig
    var windowManagement: WindowManagementConfig
    var appShortcuts: AppShortcutsConfig

    static let `default` = AppConfig(
        version: 2,
        launchAtLogin: false,
        desktop: .default,
        commandTab: .default,
        windowManagement: .default,
        appShortcuts: .default
    )
}

/// Outcome of reading `config.toml` from disk.
enum ConfigLoadResult: Equatable {
    /// No file (including a dangling symlink). Caller may use defaults and write a starter.
    case missing
    /// Readable file parsed successfully (invalid fields still count as success).
    case loaded(AppConfig, modifiedAt: Date)
    /// File exists but could not be read (oversized, non-UTF-8, outside `$HOME`, I/O error).
    case failed
}

struct ConfigStore {
    /// Hard cap matching Carbon digit hotkeys (1…9).
    static let maxHotkeySpace = 9
    /// Hard cap for `[app_shortcuts.entry.N]` rows.
    static let maxAppShortcuts = 32
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

    static func load() -> ConfigLoadResult { standard.load() }

    static func save(_ config: AppConfig) throws { try standard.save(config) }

    static func ensureExampleIfMissing() { standard.ensureExampleIfMissing() }

    // MARK: - Instance API

    /// Modification date of the resolved config file, or `nil` when no file exists.
    func resolvedModificationDate() -> Date? {
        let url = configFileURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let attrs = try? fileManager.attributesOfItem(atPath: resolved.path)
        return attrs?[.modificationDate] as? Date
    }

    func load() -> ConfigLoadResult {
        let url = configFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            log.info("No config at \(url.path, privacy: .public); using defaults")
            return .missing
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
                    "Config at \(resolved.path, privacy: .public) exceeds \(Self.maxConfigBytes) bytes; load failed"
                )
                return .failed
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let config = MinimalTOML.parseAltitudeConfig(text)
            let modifiedAt = (try? fileManager.attributesOfItem(atPath: resolved.path))?[.modificationDate] as? Date
                ?? Date.distantPast
            log.info("Loaded config version \(config.version) from \(url.path, privacy: .public)")
            return .loaded(config, modifiedAt: modifiedAt)
        } catch {
            log.error("Failed to load config: \(error.localizedDescription, privacy: .public)")
            return .failed
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

        let capped = Array(config.appShortcuts.entries.prefix(maxAppShortcuts))
        for (offset, entry) in capped.enumerated() {
            let n = offset + 1
            lines.append("")
            lines.append("[app_shortcuts.entry.\(n)]")
            lines.append("bundle_id = \(entry.bundleID)")
            lines.append("alt = \(tomlBool(entry.chord.modifiers.alt))")
            lines.append("shift = \(tomlBool(entry.chord.modifiers.shift))")
            lines.append("ctrl = \(tomlBool(entry.chord.modifiers.ctrl))")
            lines.append("cmd = \(tomlBool(entry.chord.modifiers.cmd))")
            lines.append("key = \(entry.chord.key)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderValue(_ config: AppConfig, field: ConfigField) -> String {
        let d = config.desktop
        let c = config.commandTab
        let w = config.windowManagement
        let a = config.appShortcuts
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
        case .appShortcutsEnabled: return tomlBool(a.enabled)
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
    case appShortcutsEnabled
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
    .init(section: "app_shortcuts", key: "enabled", field: .appShortcutsEnabled),
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
        var entryPartials: [Int: PartialAppShortcutEntry] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            // `#` cuts the line because values are not quoted strings in this subset.
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

            if let entryIndex = appShortcutEntryIndex(section: section) {
                applyAppShortcutEntryField(
                    entryIndex: entryIndex,
                    key: key,
                    value: value,
                    qualifiedKey: qualifiedKey,
                    entryPartials: &entryPartials,
                    ignoredKeys: &ignoredKeys
                )
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

        config.appShortcuts.entries = resolveAppShortcutEntries(entryPartials)

        return ConfigParseResult(config: config, ignoredKeys: ignoredKeys)
    }

    /// `app_shortcuts.entry.<n>` with `n` in 1…`maxAppShortcuts`.
    private static func appShortcutEntryIndex(section: String?) -> Int? {
        guard let section, section.hasPrefix("app_shortcuts.entry.") else { return nil }
        let suffix = String(section.dropFirst("app_shortcuts.entry.".count))
        guard let n = Int(suffix), (1...ConfigStore.maxAppShortcuts).contains(n) else { return nil }
        return n
    }

    private static func applyAppShortcutEntryField(
        entryIndex: Int,
        key: String,
        value: String,
        qualifiedKey: String,
        entryPartials: inout [Int: PartialAppShortcutEntry],
        ignoredKeys: inout [String]
    ) {
        var partial = entryPartials[entryIndex] ?? PartialAppShortcutEntry()
        switch key {
        case "bundle_id":
            if let id = parseBundleID(value) {
                partial.bundleID = id
            } else {
                warnInvalid(qualifiedKey, value)
                partial.bundleID = nil
            }
        case "alt":
            assignModifier(&partial.modifiers.alt, value, qualifiedKey)
        case "shift":
            assignModifier(&partial.modifiers.shift, value, qualifiedKey)
        case "ctrl":
            assignModifier(&partial.modifiers.ctrl, value, qualifiedKey)
        case "cmd":
            assignModifier(&partial.modifiers.cmd, value, qualifiedKey)
        case "key":
            if let token = parseAppShortcutKey(value) {
                partial.key = token
            } else {
                warnInvalid(qualifiedKey, value)
                partial.key = nil
            }
        default:
            ignoredKeys.append(qualifiedKey)
            log.warning("Ignoring unknown config key \(qualifiedKey, privacy: .public)")
            return
        }
        entryPartials[entryIndex] = partial
    }

    private static func resolveAppShortcutEntries(
        _ partials: [Int: PartialAppShortcutEntry]
    ) -> [AppShortcutEntry] {
        let none = ModifierFlags(alt: false, shift: false, ctrl: false, cmd: false)
        var entries: [AppShortcutEntry] = []
        for n in partials.keys.sorted() {
            guard entries.count < ConfigStore.maxAppShortcuts else { break }
            guard let partial = partials[n],
                  let bundleID = partial.bundleID, !bundleID.isEmpty,
                  let key = partial.key
            else {
                continue
            }
            entries.append(AppShortcutEntry(
                bundleID: bundleID,
                chord: KeyChord(
                    modifiers: partial.modifiers.resolved(defaults: none),
                    key: key
                )
            ))
        }
        return entries
    }

    private static func parseBundleID(_ value: String) -> String? {
        var text = value
        if text.count >= 2 {
            if text.hasPrefix("\""), text.hasSuffix("\"") {
                text = String(text.dropFirst().dropLast())
            } else if text.hasPrefix("'"), text.hasSuffix("'") {
                text = String(text.dropFirst().dropLast())
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
        case .appShortcutsEnabled:
            if let bool = parseBool(value) { config.appShortcuts.enabled = bool } else { warnInvalid(qualifiedKey, value) }
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

    /// Unquoted a–z or 0–9 for App Shortcuts (case-insensitive letters). Quoted values are invalid.
    private static func parseAppShortcutKey(_ value: String) -> Character? {
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            return nil
        }
        guard value.count == 1, let c = value.lowercased().first else { return nil }
        if ("a"..."z").contains(c) || ("0"..."9").contains(c) {
            return c
        }
        return nil
    }

    /// Accepts true/false plus yes/no/1/0 (case-insensitive).
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
