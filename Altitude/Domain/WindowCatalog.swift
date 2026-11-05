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

    /// Command-Tab / App Shortcuts AX listing: keep standard windows; drop dialogs and floaters.
    /// Empty subrole is allowed (some apps omit it). Does not require `AXStandardWindow`.
    static func acceptsSwitchSubrole(_ subrole: String) -> Bool {
        switch subrole {
        case "AXUnknown", "AXSystemDialog", "AXDialog", "AXFloatingWindow":
            return false
        default:
            return true
        }
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

    /// Prefer a specific title over empty / the bare app name when collapsing twins.
    static func preferredTitle(_ a: String, _ b: String, appName: String) -> String {
        let aWeak = isWeakTitle(a, appName: appName)
        let bWeak = isWeakTitle(b, appName: appName)
        if aWeak && !bWeak { return b }
        if bWeak && !aWeak { return a }
        if a.isEmpty, !b.isEmpty { return b }
        return a
    }

    static func preferredWindowID(_ a: CGWindowID?, _ b: CGWindowID?) -> CGWindowID? {
        if let a, a != 0 { return a }
        if let b, b != 0 { return b }
        return nil
    }

    /// Whether two Command-Tab slots refer to the same window. Non-zero window IDs win when both sides have them.
    static func sameSwitchInstance(
        pid: pid_t,
        windowID: CGWindowID?,
        title: String,
        width: Double,
        height: Double,
        otherPID: pid_t,
        otherWindowID: CGWindowID?,
        otherTitle: String,
        otherWidth: Double,
        otherHeight: Double
    ) -> Bool {
        guard pid == otherPID else { return false }
        if let left = windowID, let right = otherWindowID, left != 0, right != 0 {
            return left == right
        }
        return title == otherTitle
            && abs(width - otherWidth) < 2
            && abs(height - otherHeight) < 2
    }

    static func sameListedSize(_ a: ListedWindow, _ b: ListedWindow) -> Bool {
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// Same CG id, or same size with equal / weak titles — not two strong different titles.
    static func isSameListedWindow(_ a: ListedWindow, _ b: ListedWindow, appName: String) -> Bool {
        if let left = a.id, let right = b.id, left != 0, left == right {
            return true
        }
        guard sameListedSize(a, b) else { return false }
        if a.title == b.title { return true }
        return isWeakTitle(a.title, appName: appName)
            || isWeakTitle(b.title, appName: appName)
    }

    static func collapseListed(_ existing: ListedWindow, with other: ListedWindow, appName: String) -> ListedWindow {
        ListedWindow(
            id: preferredWindowID(existing.id, other.id),
            title: preferredTitle(existing.title, other.title, appName: appName),
            width: existing.width,
            height: existing.height,
            main: existing.main || other.main
        )
    }

    /// Same size with equal or weak titles means one window on the window-server list.
    /// Teams (and similar) publish twins there — often one empty / app-named and one specific.
    static func dedupe(_ windows: [ListedWindow], appName: String) -> [ListedWindow] {
        var kept: [ListedWindow] = []
        for window in windows {
            if let index = kept.firstIndex(where: { isSameListedWindow($0, window, appName: appName) }) {
                kept[index] = collapseListed(kept[index], with: window, appName: appName)
            } else {
                kept.append(window)
            }
        }
        return kept
    }

    /// Arc/Teams keep offscreen 500×500 / 800×600 helpers; title is often empty or just the app name.
    static func isHiddenHelper(
        width: Double,
        height: Double,
        title: String,
        onscreen: Bool,
        appName: String
    ) -> Bool {
        guard isWeakTitle(title, appName: appName) else { return false }
        if onscreen { return false }
        return (width == 500 && height == 500) || (width == 800 && height == 600)
    }

    /// Accessibility covers the current Space; the window-server list adds windows on other Spaces.
    /// Pass `nil` for `isOnActiveSpace` when AX is empty (append unmatched CG). When non-nil,
    /// unmatched CG windows reported as on the active Space are dropped; others are appended.
    static func mergeWindows(
        ax: [ListedWindow],
        cg: [ListedWindow],
        appName: String,
        isOnActiveSpace: ((CGWindowID) -> Bool)?
    ) -> [ListedWindow] {
        var merged = ax
        // Accessibility already omitted panels on this Space; CG still lists some (Rex Settings).
        // Trust AX for the active Space; only append CG windows that live strictly elsewhere.
        for window in cg {
            if let index = merged.firstIndex(where: { isSameListedWindow($0, window, appName: appName) }) {
                // Keep AX order / main; absorb the stronger title and best id from CG.
                merged[index] = collapseListed(merged[index], with: window, appName: appName)
                continue
            }
            if let isOnActiveSpace, let id = window.id, isOnActiveSpace(id) {
                continue
            }
            merged.append(window)
        }
        return merged
    }
}

private extension ListedWindow {
    var area: Double { width * height }
}
