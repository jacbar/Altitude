import Foundation

/// Which system-motion behaviors the event taps should drive.
struct SystemMotionMode: Equatable, Sendable {
    /// Swallow trackpad Space swipes, Control-Left/Right, and hop on external app activation.
    var suppressDesktopMotion: Bool
    /// Replace the system Command-Tab switcher with Altitude's window row.
    var commandTabEnabled: Bool
    /// Skip the slide when landing on the highlighted Command-Tab window.
    var commandTabInstantLanding: Bool

    var wantsTaps: Bool { suppressDesktopMotion || commandTabEnabled }

    static let off = SystemMotionMode(
        suppressDesktopMotion: false,
        commandTabEnabled: false,
        commandTabInstantLanding: false
    )
}
