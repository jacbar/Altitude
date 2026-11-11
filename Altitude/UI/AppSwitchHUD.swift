import AppKit
import Foundation

/// Still row of running apps shown while Command is held. It does not fade or slide.
@MainActor
final class AppSwitchHUD {
    var onHoverIndex: ((Int) -> Void)?
    var onClickIndex: ((Int) -> Void)?

    private let panel: NSPanel
    private let effect: NSVisualEffectView
    private let nameField = NSTextField(labelWithString: "")
    private let iconHost = IconRowView()
    private let highlight = NSView()
    private var rowPIDs: [pid_t] = []
    private var rowSide: CGFloat = 0
    private var icons: [pid_t: NSImage] = [:]

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.worksWhenModal = true

        effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        iconHost.wantsLayer = false
        iconHost.onHoverIndex = { [weak self] index in
            self?.onHoverIndex?(index)
        }
        iconHost.onClickIndex = { [weak self] index in
            self?.onClickIndex?(index)
        }
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = .labelColor
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingTail
        nameField.drawsBackground = false
        nameField.isBezeled = false
        nameField.isEditable = false
        effect.addSubview(iconHost)
        effect.addSubview(nameField)
    }

    func show(targets: [SwitchTarget], selectedIndex: Int) {
        guard !targets.isEmpty else {
            hide()
            return
        }
        let index = min(max(selectedIndex, 0), targets.count - 1)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let maxWidth = (screen?.visibleFrame.width ?? 1280) - 48
        let paddingX: CGFloat = 16
        let paddingTop: CGFloat = 14
        let nameGap: CGFloat = 8
        let nameHeight: CGFloat = 18
        let paddingBottom: CGFloat = 12
        let iconGap: CGFloat = 8
        let count = CGFloat(targets.count)
        let gaps = iconGap * max(count - 1, 0)
        let available = max(maxWidth - paddingX * 2 - gaps, count)
        let iconSide = min(64, floor(available / count))
        let rowWidth = count * iconSide + gaps
        let width = min(maxWidth, rowWidth + paddingX * 2)
        let height = paddingTop + iconSide + nameGap + nameHeight + paddingBottom

        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: width, height: height)
        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        )
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true, animate: false)

        let rowX = (width - rowWidth) / 2
        iconHost.frame = NSRect(x: rowX, y: paddingBottom + nameHeight + nameGap, width: rowWidth, height: iconSide)
        iconHost.iconSide = iconSide
        iconHost.iconGap = iconGap
        iconHost.iconCount = targets.count
        nameField.frame = NSRect(x: paddingX, y: paddingBottom, width: width - paddingX * 2, height: nameHeight)
        nameField.stringValue = targets[index].title

        let pids = targets.map { $0.app.processIdentifier }
        if pids != rowPIDs || iconSide != rowSide {
            rebuildRow(targets: targets, iconSide: iconSide, iconGap: iconGap)
            rowPIDs = pids
            rowSide = iconSide
        }
        let originX = CGFloat(index) * (iconSide + iconGap)
        highlight.frame = NSRect(x: originX - 4, y: -4, width: iconSide + 8, height: iconSide + 8)

        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    private func rebuildRow(targets: [SwitchTarget], iconSide: CGFloat, iconGap: CGFloat) {
        iconHost.subviews.forEach { $0.removeFromSuperview() }
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        highlight.layer?.cornerRadius = 10
        iconHost.addSubview(highlight)
        for (offset, target) in targets.enumerated() {
            let originX = CGFloat(offset) * (iconSide + iconGap)
            let iconView = NSImageView(frame: NSRect(x: originX, y: 0, width: iconSide, height: iconSide))
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.image = icon(for: target)
            iconHost.addSubview(iconView)
        }
    }

    private func icon(for target: SwitchTarget) -> NSImage? {
        let pid = target.app.processIdentifier
        if let cached = icons[pid] { return cached }
        guard let image = (target.app.icon ?? NSImage(named: NSImage.applicationIconName))?.copy() as? NSImage else {
            return nil
        }
        icons[pid] = image
        return image
    }

    func hide() {
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }
}

/// Icon row that hit-tests hover/click to a slot index. Gaps and outside the row are ignored.
private final class IconRowView: NSView {
    var iconSide: CGFloat = 0
    var iconGap: CGFloat = 0
    var iconCount: Int = 0
    var onHoverIndex: ((Int) -> Void)?
    var onClickIndex: ((Int) -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect,
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        onClickIndex?(index)
    }

    private func reportHover(at point: NSPoint) {
        // Notify even for the same index so the session idle timer refreshes while the pointer rests.
        guard let index = index(at: point) else { return }
        onHoverIndex?(index)
    }

    private func index(at point: NSPoint) -> Int? {
        guard iconCount > 0, iconSide > 0 else { return nil }
        guard point.y >= 0, point.y <= bounds.height else { return nil }
        let stride = iconSide + iconGap
        let i = Int(floor(point.x / stride))
        guard i >= 0, i < iconCount else { return nil }
        let localX = point.x - CGFloat(i) * stride
        guard localX >= 0, localX <= iconSide else { return nil }
        return i
    }
}
