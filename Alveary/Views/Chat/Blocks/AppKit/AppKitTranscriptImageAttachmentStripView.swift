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
    private let imageView = NSImageView()

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

    func configure(_ attachment: LocalImageAttachment) {
        imageView.image = NSImage(contentsOf: attachment.fileURL)
        toolTip = attachment.label
        setAccessibilityLabel(attachment.label)
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

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
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
}
#endif
