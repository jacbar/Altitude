import Foundation

struct CommandTabSlot<Window>: Equatable where Window: Equatable {
    var appID: Int64
    var window: Window?
}

/// Builds the Command-Tab row: each app's windows as one contiguous block (caller
/// passes the front app first, then other apps in MRU order). Apps with no windows
/// trail after every windowed app.
func commandTabRow<Window: Equatable>(
    apps: [(appID: Int64, windows: [Window])]
) -> [CommandTabSlot<Window>] {
    var windowed: [CommandTabSlot<Window>] = []
    var empty: [CommandTabSlot<Window>] = []
    for app in apps {
        if app.windows.isEmpty {
            empty.append(CommandTabSlot(appID: app.appID, window: nil))
        } else {
            for window in app.windows {
                windowed.append(CommandTabSlot(appID: app.appID, window: window))
            }
        }
    }
    return windowed + empty
}

/// Index to highlight when opening Command-Tab (`forward`) or Command-Shift-Tab.
func commandTabOpeningIndex(appIDs: [Int64], frontAppID: Int64, forward: Bool) -> Int {
    guard appIDs.count >= 2 else { return 0 }
    if !forward {
        return appIDs.count - 1
    }
    if let index = appIDs.firstIndex(where: { $0 != frontAppID }) {
        return index
    }
    return 1
}
