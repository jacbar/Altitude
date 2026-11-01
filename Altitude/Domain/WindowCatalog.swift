import CoreGraphics
import Foundation

struct ListedWindow: Equatable, Sendable {
    let id: CGWindowID?
    let title: String
    let width: Double
    let height: Double
    var main: Bool = false
}

enum WindowCatalog {
    /// Empty, or the app's localized name — too generic to treat as a distinct window identity.
    static func isWeakTitle(_ title: String, appName: String) -> Bool {
        if title.isEmpty { return true }
        return !appName.isEmpty && title == appName
    }

    /// Drop weak-title surfaces clearly smaller than the largest real window (under ~95% area).
    /// Strong titles always survive. Near-tie weaks are kept. A lone weak with no strong is unchanged.
    static func collapseRedundantWeakWindows(
        _ windows: [ListedWindow],
        appName: String
    ) -> [ListedWindow] {
        let strong = windows.filter { !isWeakTitle($0.title, appName: appName) }
        let weak = windows.filter { isWeakTitle($0.title, appName: appName) }

        if strong.isEmpty, weak.count <= 1 {
            return windows
        }

        let referenceArea: Double
        if let maxStrong = strong.map(\.area).max() {
            referenceArea = maxStrong
        } else {
            referenceArea = weak.map(\.area).max() ?? 0
        }

        let threshold = 0.95 * referenceArea
        return windows.filter { window in
            if !isWeakTitle(window.title, appName: appName) { return true }
            return window.area >= threshold
        }
    }
}

private extension ListedWindow {
    var area: Double { width * height }
}
