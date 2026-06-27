@preconcurrency import AppKit

/// Square preview tile for a local image attachment.
///
/// Transcript rows configure this as an open-only image button. Composer strips
/// additionally provide `onRemoveAttachment`, which reveals the shared remove
/// overlay without changing the underlying image layout.
@MainActor
final class AppKitImageAttachmentTileView: AppKitDynamicColorView {
    let imageView = AppKitAspectFillImageView()
    private let removeButton = AppKitAttachmentRemoveButton()
    private var attachment: LocalImageAttachment?
    var onOpenAttachment: ((LocalImageAttachment) -> Void)? {
        didSet {
            updateOpenState()
        }
    }
    var onRemoveAttachment: ((LocalImageAttachment) -> Void)? {
        didSet {
            updateRemoveState()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateCursorRectsIfPossible()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            updateRemoveButtonFrame()
            invalidateCursorRectsIfPossible()
        }
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        updateRemoveButtonFrame()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if removeButtonConsumesClick(at: point) {
            return
        }
        guard bounds.contains(point),
              performOpen() else {
            super.mouseUp(with: event)
            return
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !removeButton.isHidden {
            addCursorRect(removeButtonFrame, cursor: .pointingHand)
        }
        if onOpenAttachment != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        performOpen()
    }

    /// Updates the tile image, tooltip, and accessibility label.
    func configure(_ attachment: LocalImageAttachment) {
        self.attachment = attachment
        imageView.image = NSImage(contentsOf: attachment.fileURL)
        toolTip = attachment.label
        setAccessibilityLabel(attachment.label)
        removeButton.toolTip = "Remove \(attachment.label)"
    }

    @discardableResult
    private func performOpen() -> Bool {
        guard let attachment,
              let onOpenAttachment else {
            return false
        }
        onOpenAttachment(attachment)
        return true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = BlockInputComposerStyle.imagePreviewCornerRadius
        layer?.borderWidth = BlockInputComposerStyle.imagePreviewBorderWidth
        layer?.masksToBounds = true
        setLayerFillColor(transcriptImageAttachmentFillColor)
        setLayerStrokeColorPreservingResolvedAlpha { _ in
            transcriptImageAttachmentBorderColor
        }

        imageView.cornerRadius = BlockInputComposerStyle.imagePreviewCornerRadius
        addSubview(imageView)

        removeButton.onPress = { [weak self] in
            guard let self, let attachment = self.attachment else {
                return
            }
            self.onRemoveAttachment?(attachment)
        }
        addSubview(removeButton)

        setAccessibilityElement(true)
        updateOpenState()
        updateRemoveState()
    }

    private func updateOpenState() {
        setAccessibilityRole(onOpenAttachment == nil ? .image : .button)
        invalidateCursorRectsIfPossible()
    }

    private func updateRemoveState() {
        removeButton.isHidden = onRemoveAttachment == nil
        invalidateCursorRectsIfPossible()
    }

    private func removeButtonConsumesClick(at point: NSPoint) -> Bool {
        guard !removeButton.isHidden,
              removeButtonFrame.contains(point) else {
            return false
        }
        return removeButton.performPress()
    }

    private var removeButtonFrame: NSRect {
        NSRect(
            x: max(bounds.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width - 5, 0),
            y: 5,
            width: BlockInputComposerStyle.imagePreviewRemoveButtonSize.width,
            height: BlockInputComposerStyle.imagePreviewRemoveButtonSize.height
        )
    }

    private func updateRemoveButtonFrame() {
        removeButton.frame = removeButtonFrame
    }

    private func invalidateCursorRectsIfPossible() {
        window?.invalidateCursorRects(for: self)
    }
}

/// Fill color shared by local image and app-shot attachment preview surfaces.
let transcriptImageAttachmentFillColor = NSColor(name: nil) { appearance in
    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
        return NSColor(calibratedWhite: 0.1176470588, alpha: 1)
    default:
        return NSColor(calibratedWhite: 0.965, alpha: 1)
    }
}

/// Border color shared by local image and app-shot attachment preview surfaces.
let transcriptImageAttachmentBorderColor = NSColor(name: nil) { appearance in
    let resolved = NSColor.secondaryLabelColor.resolved(for: appearance)
    return resolved.withAlphaComponent(resolved.alphaComponent * 0.10)
}

/// Circular remove control used by staged composer attachment previews.
@MainActor
final class AppKitAttachmentRemoveButton: NSView {
    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let appearance = appKitRenderingAppearance
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        BlockInputComposerStyle.imagePreviewRemoveButtonBackgroundColor.resolved(for: appearance).setFill()
        path.fill()
        BlockInputComposerStyle.imagePreviewRemoveButtonBorderColor.resolved(for: appearance).setStroke()
        path.lineWidth = BlockInputComposerStyle.imagePreviewRemoveButtonBorderWidth
        path.stroke()

        let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        symbol?.isTemplate = true
        let symbolSize = NSSize(width: 8, height: 8)
        let symbolRect = NSRect(
            x: bounds.midX - symbolSize.width / 2,
            y: bounds.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        BlockInputComposerStyle.imagePreviewRemoveButtonSymbolColor.set()
        symbol?.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseUp(with: event)
            return
        }
        performPress()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func accessibilityPerformPress() -> Bool {
        performPress()
    }

    private func setup() {
        wantsLayer = true
        layer?.shadowColor = BlockInputComposerStyle.imagePreviewRemoveButtonShadowColor.cgColor
        layer?.shadowOpacity = BlockInputComposerStyle.imagePreviewRemoveButtonShadowOpacity
        layer?.shadowRadius = BlockInputComposerStyle.imagePreviewRemoveButtonShadowRadius
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Remove attachment")
    }

    @discardableResult
    func performPress() -> Bool {
        guard let onPress else {
            return false
        }
        onPress()
        return true
    }
}
