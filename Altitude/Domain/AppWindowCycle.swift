import CoreGraphics
import Foundation

/// Picks the next window when an App Shortcut is pressed again while that app is frontmost.
enum AppWindowCycle {
    /// Keep `previous` when it is the same set of windows, so raising one does not
    /// reshuffle z-order and bounce between the front two. Titles and the main flag
    /// refresh from `latest`. A new or closed window adopts `latest` as-is.
    static func stabilizedOrder(
        previous: [ListedWindow]?,
        latest: [ListedWindow]
    ) -> [ListedWindow] {
        guard let previous, !previous.isEmpty else { return latest }
        let latestKeys = latest.map(identity)
        guard latestKeys.count == Set(latestKeys).count else { return latest }
        let previousKeys = previous.map(identity)
        guard previousKeys.count == Set(previousKeys).count,
              Set(previousKeys) == Set(latestKeys)
        else { return latest }
        let latestByKey = Dictionary(uniqueKeysWithValues: zip(latestKeys, latest))
        let refreshed = previousKeys.compactMap { latestByKey[$0] }
        guard refreshed.count == previousKeys.count else { return latest }
        return refreshed
    }

    /// Window to focus on this press. Nil when there are fewer than two windows.
    /// `pending` is the window the previous press asked to raise, used until focus catches up.
    /// Unknown focus lands on the first window in `order`.
    static func next(
        order: [ListedWindow],
        focusedID: CGWindowID?,
        pending: ListedWindow? = nil
    ) -> ListedWindow? {
        guard order.count >= 2 else { return nil }
        let index: Int
        if let pending, let pendingIndex = position(of: pending, in: order) {
            index = pendingIndex
        } else if let focusedID, focusedID != 0,
                  let focusedIndex = order.firstIndex(where: { $0.id == focusedID }) {
            index = focusedIndex
        } else if let mainIndex = order.firstIndex(where: \.main) {
            index = mainIndex
        } else {
            return order[0]
        }
        return order[(index + 1) % order.count]
    }

    private static func position(of needle: ListedWindow, in order: [ListedWindow]) -> Int? {
        let needleKey = identity(needle)
        return order.firstIndex { identity($0) == needleKey }
    }

    private static func identity(_ window: ListedWindow) -> String {
        if let id = window.id, id != 0 {
            return "id:\(id)"
        }
        return "geom:\(window.title)|\(window.width)|\(window.height)"
    }
}
