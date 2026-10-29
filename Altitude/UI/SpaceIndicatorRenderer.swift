import AppKit

/// Draws numbered desktop boxes for the menu bar.
enum SpaceIndicatorRenderer {
    private static let canvasHeight: CGFloat = 18
    private static let boxSize: CGFloat = 16
    private static let gap: CGFloat = 3
    private static let padding: CGFloat = 1
    private static let cornerRadius: CGFloat = 3

    static func image(snapshot: SpaceSnapshot) -> NSImage {
        let spaces = snapshot.spaces
        if spaces.isEmpty {
            return textTemplate("—", height: canvasHeight)
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let widths = spaces.map { boxWidth(for: $0.index, font: font) }
        let width = padding * 2
            + widths.reduce(CGFloat(0), +)
            + CGFloat(max(spaces.count - 1, 0)) * gap
        let size = NSSize(width: width, height: canvasHeight)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return textTemplate("Alt", height: canvasHeight)
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .high
        context?.shouldAntialias = true
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        var x = padding
        let y = (canvasHeight - boxSize) / 2
        for (space, boxWidth) in zip(spaces, widths) {
            let rect = NSRect(x: x, y: y, width: boxWidth, height: boxSize)
            drawBox(index: space.index, isCurrent: space.isCurrent, in: rect, font: font)
            x += boxWidth + gap
        }

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func boxWidth(for index: Int, font: NSFont) -> CGFloat {
        let textWidth = ("\(index)" as NSString).size(withAttributes: [.font: font]).width
        return max(boxSize, ceil(textWidth + 8))
    }

    private static func drawBox(index: Int, isCurrent: Bool, in rect: NSRect, font: NSFont) {
        let label = "\(index)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textSize = label.size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: (rect.midX - textSize.width / 2).rounded(),
            y: rect.midY - textSize.height / 2
        )

        if isCurrent {
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.setFill()
            path.fill()
            // Template images tint every opaque pixel the same color, so the
            // digit is punched out of the fill instead of painted on top.
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            label.draw(at: textOrigin, withAttributes: attributes)
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(
                roundedRect: inset,
                xRadius: max(cornerRadius - 0.5, 0),
                yRadius: max(cornerRadius - 0.5, 0)
            )
            path.lineWidth = 1
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            label.draw(at: textOrigin, withAttributes: attributes)
        }
    }

    private static func textTemplate(_ string: String, height: CGFloat) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = (string as NSString).size(withAttributes: attrs)
        let size = NSSize(width: max(textSize.width + 4, 16), height: height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            let fallback = NSImage(size: size)
            fallback.isTemplate = true
            return fallback
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (string as NSString).draw(
            at: NSPoint(x: 2, y: (height - textSize.height) / 2),
            withAttributes: attrs
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
