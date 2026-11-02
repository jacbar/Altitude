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
        app.processIdentifier == other.app.processIdentifier
            && title == other.title
            && abs(width - other.width) < 2
            && abs(height - other.height) < 2
    }
}
