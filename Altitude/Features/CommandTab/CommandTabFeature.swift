import Foundation

enum CommandTabFeature {
    static func motionMode(config: AppConfig) -> SystemMotionMode {
        SystemMotionMode(
            suppressDesktopMotion: config.desktop.enabled && config.desktop.disableMotion,
            commandTabEnabled: config.commandTab.enabled,
            commandTabInstantLanding: config.commandTab.enabled && config.commandTab.disableMotion
        )
    }
}
