@preconcurrency import AppKit

/// Compact preview chip for a staged non-image local file attachment.
///
/// Composer attachment strips use this beside image tiles and app-shot cards.
/// The view owns only rendering and interaction; host code decides how opening
/// and removing a staged file should mutate app state.
@MainActor
final class AppKitFileAttachmentChipView: AppKitDynamicColorView {
    static let preferredSize = NSSize(width: 240, height: 76)

    private static let cornerRadius: CGFloat = 8
    private static let iconSize = NSSize(width: 28, height: 32)
    private static let horizontalPadding: CGFloat = 12
    private static let iconTitleSpacing: CGFloat = 6
    private static let titleTypeSpacing: CGFloat = 5

    private let iconImageView = AppKitDynamicTintImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let typeField = NSTextField(labelWithString: "")
    private let removeButton = AppKitAttachmentRemoveButton()
    private var attachment: LocalFileAttachment?

    var onOpenAttachment: ((LocalFileAttachment) -> Void)? {
        didSet {
            updateOpenState()
        }
    }
    var onRemoveAttachment: ((LocalFileAttachment) -> Void)? {
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

    // The strip can relayout chips by changing only their origin; refresh cursor
    // rects so the full-card pointing-hand region follows the moved card.
    override var frame: NSRect {
        didSet {
            guard oldValue.origin != frame.origin else {
                return
            }
            invalidateCursorRectsIfPossible()
        }
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

        iconImageView.frame = NSRect(
            x: Self.horizontalPadding,
            y: max((bounds.height - Self.iconSize.height) / 2, 0),
            width: Self.iconSize.width,
            height: Self.iconSize.height
        )

        let textX = iconImageView.frame.maxX + Self.iconTitleSpacing
        let trailingInset = Self.horizontalPadding + (removeButton.isHidden ? 0 : BlockInputComposerStyle.imagePreviewRemoveButtonSize.width + 8)
        let textWidth = max(bounds.width - textX - trailingInset, 0)
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        let typeHeight = ceil(typeField.intrinsicContentSize.height)
        let textHeight = titleHeight + Self.titleTypeSpacing + typeHeight
        let textY = max((bounds.height - textHeight) / 2, 0)
        titleField.frame = NSRect(x: textX, y: textY, width: textWidth, height: titleHeight)
        typeField.frame = NSRect(
            x: textX,
            y: titleField.frame.maxY + Self.titleTypeSpacing,
            width: textWidth,
            height: typeHeight
        )
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        if !removeButton.isHidden,
           removeButtonFrame.contains(point) {
            updateRemoveButtonFrame()
            let removePoint = convert(point, to: removeButton)
            if let hit = removeButton.hitTest(removePoint) {
                return hit
            }
        }
        return self
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

    /// Updates the file chip icon, label, type text, tooltip, and accessibility label.
    func configure(_ attachment: LocalFileAttachment) {
        self.attachment = attachment
        titleField.stringValue = attachment.label
        typeField.stringValue = attachment.typeLabel
        toolTip = attachment.label
        setAccessibilityLabel("\(attachment.label), \(attachment.typeLabel)")
        removeButton.toolTip = "Remove \(attachment.label)"
        needsLayout = true
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
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = BlockInputComposerStyle.imagePreviewBorderWidth
        layer?.masksToBounds = true
        setLayerFillColor(transcriptImageAttachmentFillColor)
        setLayerStrokeColorPreservingResolvedAlpha { _ in
            transcriptImageAttachmentBorderColor
        }

        let documentIcon = NSImage(systemSymbolName: "document", accessibilityDescription: nil) ??
            NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        documentIcon?.isTemplate = true
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.setDynamicContentTintColor(.secondaryLabelColor)
        iconImageView.image = documentIcon
        addSubview(iconImageView)

        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)

        typeField.font = .systemFont(ofSize: 13, weight: .regular)
        typeField.lineBreakMode = .byTruncatingTail
        typeField.maximumNumberOfLines = 1
        typeField.cell?.truncatesLastVisibleLine = true
        typeField.textColor = .secondaryLabelColor
        typeField.backgroundColor = .clear
        typeField.isBordered = false
        typeField.isEditable = false
        typeField.isSelectable = false
        addSubview(typeField)

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
        setAccessibilityRole(onOpenAttachment == nil ? .group : .button)
        invalidateCursorRectsIfPossible()
    }

    private func updateRemoveState() {
        removeButton.isHidden = onRemoveAttachment == nil
        needsLayout = true
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
            x: max(bounds.maxX - BlockInputComposerStyle.imagePreviewRemoveButtonSize.width - 8, 0),
            y: 8,
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

#if DEBUG
extension AppKitFileAttachmentChipView {
    var iconImageForTesting: NSImage? {
        iconImageView.image
    }

    var iconFrameForTesting: CGRect {
        iconImageView.frame
    }

    var titleFrameForTesting: CGRect {
        titleField.frame
    }

    var titleFontSizeForTesting: CGFloat {
        titleField.font?.pointSize ?? 0
    }
}
#endif
