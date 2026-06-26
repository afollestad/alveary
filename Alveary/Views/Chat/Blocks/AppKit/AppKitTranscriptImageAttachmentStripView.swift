@preconcurrency import AppKit

@MainActor
final class AppKitTranscriptImageAttachmentStripView: NSView {
    static var thumbnailSize: NSSize {
        BlockInputComposerStyle.imagePreviewThumbnailSize
    }

    static var interItemSpacing: CGFloat {
        BlockInputComposerStyle.imagePreviewInterItemSpacing
    }

    private var attachments: [LocalImageAttachment] = []
    private var tileViews: [AppKitTranscriptImageAttachmentTileView] = []
    var onOpenAttachment: ((LocalImageAttachment) -> Void)? {
        didSet {
            tileViews.forEach { $0.onOpenAttachment = onOpenAttachment }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func configure(_ attachments: [LocalImageAttachment]) {
        guard self.attachments != attachments else {
            return
        }
        self.attachments = attachments

        if tileViews.count < attachments.count {
            for _ in tileViews.count..<attachments.count {
                let tileView = AppKitTranscriptImageAttachmentTileView()
                tileView.onOpenAttachment = onOpenAttachment
                tileViews.append(tileView)
                addSubview(tileView)
            }
        }

        for (index, tileView) in tileViews.enumerated() {
            if attachments.indices.contains(index) {
                tileView.configure(attachments[index])
                tileView.isHidden = false
            } else {
                tileView.isHidden = true
            }
        }
        needsLayout = true
    }

    func measuredSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        guard !attachments.isEmpty else {
            return .zero
        }
        let columnCount = columnCount(constrainedTo: maxWidth)
        let visibleColumnCount = min(columnCount, attachments.count)
        let rowCount = Int(ceil(Double(attachments.count) / Double(columnCount)))
        return NSSize(
            width: CGFloat(visibleColumnCount) * Self.thumbnailSize.width +
                CGFloat(max(visibleColumnCount - 1, 0)) * Self.interItemSpacing,
            height: CGFloat(rowCount) * Self.thumbnailSize.height +
                CGFloat(max(rowCount - 1, 0)) * Self.interItemSpacing
        )
    }

    override func layout() {
        super.layout()
        let columnCount = columnCount(constrainedTo: bounds.width)
        for (index, tileView) in tileViews.enumerated() {
            guard attachments.indices.contains(index) else {
                tileView.frame = .zero
                continue
            }
            let column = index % columnCount
            let row = index / columnCount
            tileView.frame = NSRect(
                x: CGFloat(column) * (Self.thumbnailSize.width + Self.interItemSpacing),
                y: CGFloat(row) * (Self.thumbnailSize.height + Self.interItemSpacing),
                width: Self.thumbnailSize.width,
                height: Self.thumbnailSize.height
            )
        }
    }

    private func columnCount(constrainedTo maxWidth: CGFloat) -> Int {
        let effectiveMaxWidth = max(maxWidth, Self.thumbnailSize.width)
        return max(
            1,
            Int(floor((effectiveMaxWidth + Self.interItemSpacing) / (Self.thumbnailSize.width + Self.interItemSpacing)))
        )
    }
}

@MainActor
private final class AppKitTranscriptImageAttachmentTileView: AppKitDynamicColorView {
    private let imageView = AppKitTranscriptAspectFillImageView()
    private var attachment: LocalImageAttachment?
    var onOpenAttachment: ((LocalImageAttachment) -> Void)? {
        didSet {
            updateOpenState()
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

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)),
              performOpen() else {
            super.mouseUp(with: event)
            return
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onOpenAttachment != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        performOpen()
    }

    func configure(_ attachment: LocalImageAttachment) {
        self.attachment = attachment
        imageView.image = NSImage(contentsOf: attachment.fileURL)
        toolTip = attachment.label
        setAccessibilityLabel(attachment.label)
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

        setAccessibilityElement(true)
        updateOpenState()
    }

    private func updateOpenState() {
        setAccessibilityRole(onOpenAttachment == nil ? .image : .button)
        window?.invalidateCursorRects(for: self)
    }
}

private let transcriptImageAttachmentFillColor = NSColor(name: nil) { appearance in
    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
        return NSColor(calibratedWhite: 0.1176470588, alpha: 1)
    default:
        return NSColor(calibratedWhite: 0.965, alpha: 1)
    }
}

private let transcriptImageAttachmentBorderColor = NSColor(name: nil) { appearance in
    let resolved = NSColor.secondaryLabelColor.resolved(for: appearance)
    return resolved.withAlphaComponent(resolved.alphaComponent * 0.10)
}

private final class AppKitTranscriptAspectFillImageView: NSView {
    var image: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            layer?.cornerRadius = cornerRadius
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image,
              let imageFrame = aspectFillImageFrame else {
            return
        }
        image.draw(
            in: imageFrame,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private var aspectFillImageFrame: NSRect? {
        guard let image,
              image.size.width > 0,
              image.size.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(
            x: bounds.midX - (drawSize.width / 2),
            y: bounds.midY - (drawSize.height / 2),
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
    }
}

#if DEBUG
extension AppKitTranscriptImageAttachmentStripView {
    var tileFramesForTesting: [CGRect] {
        tileViews.prefix(attachments.count).map(\.frame)
    }

    var tileBorderColorsForTesting: [CGColor?] {
        tileViews.prefix(attachments.count).map { $0.layer?.borderColor }
    }

    var tileFillColorsForTesting: [CGColor?] {
        tileViews.prefix(attachments.count).map { $0.layer?.backgroundColor }
    }

    var tileImageFramesForTesting: [CGRect?] {
        tileViews.prefix(attachments.count).map(\.imageFrameForTesting)
    }

    var tileHitTargetsForTesting: [Bool] {
        tileViews.prefix(attachments.count).map { tileView in
            let center = NSPoint(x: tileView.bounds.midX, y: tileView.bounds.midY)
            return tileView.hitTest(center) === tileView
        }
    }

    @discardableResult
    func performOpenForTesting(at index: Int = 0) -> Bool {
        guard tileViews.indices.contains(index) else {
            return false
        }
        return tileViews[index].accessibilityPerformPress()
    }
}

extension AppKitTranscriptImageAttachmentTileView {
    var imageFrameForTesting: CGRect? {
        imageView.aspectFillImageFrameForTesting
    }
}

extension AppKitTranscriptAspectFillImageView {
    var aspectFillImageFrameForTesting: CGRect? {
        aspectFillImageFrame
    }
}
#endif
