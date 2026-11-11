import Foundation

/// Open Command-Tab switcher state: targets, selection, and idle deadline.
struct CommandTabSession<Target> {
    var targets: [Target]
    var index: Int
    var idleDeadline: Date

    /// Returns nil when there are fewer than two targets.
    static func open(
        targets: [Target],
        index: Int,
        now: Date,
        idle: TimeInterval = Timing.commandTabIdle
    ) -> CommandTabSession? {
        guard targets.count >= 2 else { return nil }
        return CommandTabSession(
            targets: targets,
            index: index,
            idleDeadline: now.addingTimeInterval(idle)
        )
    }

    /// Wraps the selection, refreshes the idle deadline, and reports whether the session should close.
    mutating func move(
        by delta: Int,
        now: Date,
        idle: TimeInterval = Timing.commandTabIdle
    ) -> Bool {
        let count = targets.count
        guard count >= 2 else { return true }
        guard delta != 0 else { return false }
        index = (index + delta % count + count) % count
        idleDeadline = now.addingTimeInterval(idle)
        return false
    }

    /// Sets the selection by absolute index, refreshes idle, and reports whether the session should close.
    /// Out-of-range indices close; an in-range index (including the current one) keeps the session open.
    mutating func select(
        index newIndex: Int,
        now: Date,
        idle: TimeInterval = Timing.commandTabIdle
    ) -> Bool {
        guard targets.indices.contains(newIndex) else { return true }
        index = newIndex
        idleDeadline = now.addingTimeInterval(idle)
        return false
    }
}
