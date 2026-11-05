import CoreGraphics

enum WindowArrangement {
    /// Cocoa bottom-left rect → Accessibility top-left origin using the primary display's `maxY`.
    static func accessibilityOrigin(cocoaRect: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: cocoaRect.minX, y: primaryMaxY - cocoaRect.maxY)
    }

    /// True when each of x, y, width, and height differs by at most `tolerance` points.
    static func framesMatch(
        expectedOrigin: CGPoint,
        expectedSize: CGSize,
        actualOrigin: CGPoint,
        actualSize: CGSize,
        tolerance: CGFloat = 2
    ) -> Bool {
        abs(expectedOrigin.x - actualOrigin.x) <= tolerance
            && abs(expectedOrigin.y - actualOrigin.y) <= tolerance
            && abs(expectedSize.width - actualSize.width) <= tolerance
            && abs(expectedSize.height - actualSize.height) <= tolerance
    }

    /// Insets `visibleFrame` by `margin` on every side. Nil when width or height is not positive.
    static func maximizedRect(visibleFrame: CGRect, margin: CGFloat) -> CGRect? {
        let rect = visibleFrame.insetBy(dx: margin, dy: margin)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// Equal full-height columns left to right. Nil when `count` < 1 or a resulting size is not positive.
    /// Index 0 is the leftmost column. `count == 1` matches `maximizedRect`.
    static func columnRects(visibleFrame: CGRect, margin: CGFloat, count: Int) -> [CGRect]? {
        guard count >= 1 else { return nil }
        let n = CGFloat(count)
        let columnWidth = (visibleFrame.width - margin * (n + 1)) / n
        let height = visibleFrame.height - 2 * margin
        guard columnWidth > 0, height > 0 else { return nil }

        return (0..<count).map { i in
            let x = visibleFrame.minX + margin + CGFloat(i) * (columnWidth + margin)
            let y = visibleFrame.minY + margin
            return CGRect(x: x, y: y, width: columnWidth, height: height)
        }
    }

    /// Indices ordered by left ascending, then top ascending. Shared prefix only when lengths differ.
    /// Stable for equal keys.
    static func sortIndices(left: [CGFloat], top: [CGFloat]) -> [Int] {
        let count = min(left.count, top.count)
        return (0..<count).sorted { a, b in
            if left[a] != left[b] { return left[a] < left[b] }
            if top[a] != top[b] { return top[a] < top[b] }
            return a < b
        }
    }

    /// AX role for arrange inclusion. Empty (flaky AX) or `AXWindow` only.
    static func acceptsArrangeRole(_ role: String) -> Bool {
        role.isEmpty || role == "AXWindow"
    }

    /// AX subrole for arrange inclusion. Looser than Command-Tab (`WindowCatalog.acceptsSwitchSubrole`):
    /// reject unknown / system dialog only so floating panels can still be arranged.
    /// Does not require `AXStandardWindow`, so Electron-style standard windows are kept.
    static func acceptsArrangeSubrole(_ subrole: String) -> Bool {
        subrole != "AXUnknown" && subrole != "AXSystemDialog"
    }

    /// How CGS space membership relates to the arrange target Space.
    enum SpaceMembership: Equatable {
        /// Window lists the arrange Space.
        case onArrangeSpace
        /// Membership empty; treat as on arrange only when arrange Space is the active Space.
        case emptyOnActiveArrangeSpace
        /// Lists other Spaces, or empty while arrange is not the active Space.
        case excluded
    }

    /// Space filter for arrange. Empty membership does not silently drop a window on the active
    /// arrange Space; windows that clearly belong elsewhere stay excluded.
    static func spaceMembership(
        windowSpaceIDs: [UInt64],
        arrangeSpaceID: UInt64,
        activeSpaceID: UInt64
    ) -> SpaceMembership {
        if windowSpaceIDs.contains(arrangeSpaceID) {
            return .onArrangeSpace
        }
        if windowSpaceIDs.isEmpty {
            return arrangeSpaceID == activeSpaceID ? .emptyOnActiveArrangeSpace : .excluded
        }
        return .excluded
    }
}
