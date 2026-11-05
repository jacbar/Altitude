import AppKit
import CoreGraphics
import Foundation

/// One Command-Tab entry. An app with two windows produces two of these.
struct SwitchTarget {
    let app: NSRunningApplication
    let windowID: CGWindowID?
    let title: String
    let width: Double
    let height: Double

    func sameInstance(as other: SwitchTarget) -> Bool {
        WindowCatalog.sameSwitchInstance(
            pid: app.processIdentifier,
            windowID: windowID,
            title: title,
            width: width,
            height: height,
            otherPID: other.app.processIdentifier,
            otherWindowID: other.windowID,
            otherTitle: other.title,
            otherWidth: other.width,
            otherHeight: other.height
        )
    }
}
