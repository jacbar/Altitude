import AppKit
import os.log

private let log = Logger(subsystem: "com.altitude.app", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let focusResolver = FocusedWindowResolver()
    private lazy var spaceService: SpaceService = SkyLightBackend(focusResolver: focusResolver)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Reinforce accessory policy early (Info.plist LSUIElement + main.swift).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hostless XCTest must not bootstrap the agent (config, menu bar, event taps).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        log.info("Altitude launching")
        ConfigStore.ensureExampleIfMissing()

        menuBar = MenuBarController(
            spaceService: spaceService,
            focusResolver: focusResolver
        )
        menuBar?.bootstrapAccessibility()
        log.info("Menu bar controller ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Altitude terminating")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
