import CoreGraphics

enum WindowArrangement {
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
}
