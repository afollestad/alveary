@preconcurrency import AppKit

/// Host-owned attachment strip rendered above the BlockInputKit composer editor.
///
/// This view owns staged attachment previews for the composer: square image
/// tiles, non-image file chips, and richer app-shot cards. BlockInputKit stays
/// responsible for the editable document below it, while Alveary owns preview
/// staging, opening, removal, and drag/drop feedback.
@MainActor
final class AppKitComposerAttachmentStripView: NSView {
    private static let contentInsets = NSEdgeInsets(
        top: BlockInputComposerStyle.imagePreviewVerticalPadding,
        left: BlockInputComposerStyle.imagePreviewHorizontalPadding,
        bottom: BlockInputComposerStyle.imagePreviewVerticalPadding,
        right: BlockInputComposerStyle.imagePreviewHorizontalPadding
    )

    private var attachments: [ComposerAttachment] = []
    private(set) var imageTileViews: [AppKitImageAttachmentTileView] = []
    private(set) var fileChipViews: [AppKitFileAttachmentChipView] = []
    private(set) var appShotCardViews: [AppKitAppShotAttachmentCardView] = []
    private var imageSizeCache: [String: NSSize] = [:]

    var onOpenAttachment: ((ComposerAttachment) -> Void)? {
        didSet {
            updateAttachmentHandlers()
        }
    }
    var onRemoveAttachment: ((ComposerAttachment) -> Void)? {
        didSet {
            updateAttachmentHandlers()
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
        let plan = layoutPlan(constrainedTo: bounds.width)
        apply(frames: plan.imageFrames, to: imageTileViews)
        apply(frames: plan.fileFrames, to: fileChipViews)
        apply(frames: plan.appShotFrames, to: appShotCardViews)
    }

    /// Updates the visible composer attachment previews.
    func configure(_ attachments: [ComposerAttachment]) {
        guard self.attachments != attachments else {
            return
        }
        self.attachments = attachments
        let images = imageAttachments
        let files = fileAttachments
        let appShots = appShotAttachments

        ensureImageTileCount(images.count)
        ensureFileChipCount(files.count)
        ensureAppShotCardCount(appShots.count)
        updateAttachmentHandlers()

        for (index, tileView) in imageTileViews.enumerated() {
            if images.indices.contains(index) {
                tileView.configure(images[index])
                tileView.isHidden = false
            } else {
                tileView.isHidden = true
            }
        }
        for (index, chipView) in fileChipViews.enumerated() {
            if files.indices.contains(index) {
                chipView.configure(files[index])
                chipView.isHidden = false
            } else {
                chipView.isHidden = true
            }
        }
        for (index, cardView) in appShotCardViews.enumerated() {
            if appShots.indices.contains(index) {
                cardView.configure(appShots[index])
                cardView.isHidden = false
            } else {
                cardView.isHidden = true
            }
        }
        needsLayout = true
        needsDisplay = true
    }

    /// Returns the strip height needed for a given width, or zero when no attachments are visible.
    func measuredHeight(width: CGFloat) -> CGFloat {
        guard !attachments.isEmpty else {
            return 0
        }
        return ceil(layoutPlan(constrainedTo: width).size.height)
    }

    var isEmpty: Bool {
        attachments.isEmpty
    }

    private var imageAttachments: [LocalImageAttachment] {
        attachments.compactMap { attachment in
            guard case .image(let image) = attachment else {
                return nil
            }
            return image
        }
    }

    private var fileAttachments: [LocalFileAttachment] {
        attachments.compactMap { attachment in
            guard case .file(let file) = attachment else {
                return nil
            }
            return file
        }
    }

    private var appShotAttachments: [AppShotAttachment] {
        attachments.compactMap { attachment in
            guard case .appShot(let appShot) = attachment else {
                return nil
            }
            return appShot
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Message attachments")
    }

    private func ensureImageTileCount(_ count: Int) {
        guard imageTileViews.count < count else {
            return
        }
        for _ in imageTileViews.count..<count {
            let tileView = AppKitImageAttachmentTileView()
            imageTileViews.append(tileView)
            addSubview(tileView)
        }
    }

    private func ensureFileChipCount(_ count: Int) {
        guard fileChipViews.count < count else {
            return
        }
        for _ in fileChipViews.count..<count {
            let chipView = AppKitFileAttachmentChipView()
            fileChipViews.append(chipView)
            addSubview(chipView)
        }
    }

    private func ensureAppShotCardCount(_ count: Int) {
        guard appShotCardViews.count < count else {
            return
        }
        for _ in appShotCardViews.count..<count {
            let cardView = AppKitAppShotAttachmentCardView()
            appShotCardViews.append(cardView)
            addSubview(cardView)
        }
    }

    private func updateAttachmentHandlers() {
        imageTileViews.forEach { tileView in
            tileView.onOpenAttachment = { [weak self] attachment in
                self?.onOpenAttachment?(.image(attachment))
            }
            tileView.onRemoveAttachment = { [weak self] attachment in
                self?.onRemoveAttachment?(.image(attachment))
            }
        }
        fileChipViews.forEach { chipView in
            chipView.onOpenAttachment = { [weak self] attachment in
                self?.onOpenAttachment?(.file(attachment))
            }
            chipView.onRemoveAttachment = { [weak self] attachment in
                self?.onRemoveAttachment?(.file(attachment))
            }
        }
        appShotCardViews.forEach { cardView in
            cardView.onOpenAttachment = { [weak self, weak cardView] in
                guard let self,
                      let cardView,
                      let index = self.appShotCardViews.firstIndex(where: { $0 === cardView }),
                      self.appShotAttachments.indices.contains(index) else {
                    return
                }
                self.onOpenAttachment?(.appShot(self.appShotAttachments[index]))
            }
            cardView.onRemoveAttachment = { [weak self, weak cardView] in
                guard let self,
                      let cardView,
                      let index = self.appShotCardViews.firstIndex(where: { $0 === cardView }),
                      self.appShotAttachments.indices.contains(index) else {
                    return
                }
                self.onRemoveAttachment?(.appShot(self.appShotAttachments[index]))
            }
        }
    }

    private func layoutPlan(constrainedTo maxWidth: CGFloat) -> ComposerAttachmentStripLayoutPlan {
        guard !attachments.isEmpty else {
            return ComposerAttachmentStripLayoutPlan(size: .zero, imageFrames: [], fileFrames: [], appShotFrames: [])
        }

        let contentInsets = Self.contentInsets
        let contentWidth = max(maxWidth - contentInsets.left - contentInsets.right, 1)
        let rowLayout = attachmentLayoutRows(constrainedTo: contentWidth)
        return layoutPlan(rows: rowLayout.rows, counts: rowLayout.counts, contentInsets: contentInsets)
    }

    private func attachmentLayoutRows(constrainedTo contentWidth: CGFloat) -> ComposerAttachmentLayoutRows {
        var rows: [ComposerAttachmentLayoutRow] = []
        var currentItems: [ComposerAttachmentLayoutItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var counts = ComposerAttachmentLayoutCounts()

        for attachment in attachments {
            let item = layoutItem(for: attachment, counts: &counts, contentWidth: contentWidth)

            let nextWidth = currentItems.isEmpty ?
                item.size.width :
                currentWidth + BlockInputComposerStyle.imagePreviewInterItemSpacing + item.size.width
            if !currentItems.isEmpty && nextWidth > contentWidth {
                appendLayoutRow(
                    items: &currentItems,
                    width: &currentWidth,
                    height: &currentHeight,
                    to: &rows
                )
            }
            let itemX = currentItems.isEmpty ? 0 : currentWidth + BlockInputComposerStyle.imagePreviewInterItemSpacing
            currentItems.append(item.withOriginX(itemX))
            currentWidth = itemX + item.size.width
            currentHeight = max(currentHeight, item.size.height)
        }

        appendLayoutRow(
            items: &currentItems,
            width: &currentWidth,
            height: &currentHeight,
            to: &rows
        )
        return ComposerAttachmentLayoutRows(rows: rows, counts: counts)
    }

    private func layoutItem(
        for attachment: ComposerAttachment,
        counts: inout ComposerAttachmentLayoutCounts,
        contentWidth: CGFloat
    ) -> ComposerAttachmentLayoutItem {
        switch attachment {
        case .image:
            defer {
                counts.image += 1
            }
            return ComposerAttachmentLayoutItem(kind: .image(counts.image), size: BlockInputComposerStyle.imagePreviewThumbnailSize)
        case .file:
            defer {
                counts.file += 1
            }
            return ComposerAttachmentLayoutItem(kind: .file(counts.file), size: AppKitFileAttachmentChipView.preferredSize)
        case .appShot(let appShot):
            defer {
                counts.appShot += 1
            }
            return ComposerAttachmentLayoutItem(
                kind: .appShot(counts.appShot),
                size: appShotCardSize(for: appShot, constrainedTo: contentWidth)
            )
        }
    }

    private func appendLayoutRow(
        items: inout [ComposerAttachmentLayoutItem],
        width: inout CGFloat,
        height: inout CGFloat,
        to rows: inout [ComposerAttachmentLayoutRow]
    ) {
        guard !items.isEmpty else {
            return
        }
        rows.append(ComposerAttachmentLayoutRow(items: items, width: width, height: height))
        items = []
        width = 0
        height = 0
    }

    private func layoutPlan(
        rows: [ComposerAttachmentLayoutRow],
        counts: ComposerAttachmentLayoutCounts,
        contentInsets: NSEdgeInsets
    ) -> ComposerAttachmentStripLayoutPlan {
        var imageFrames: [NSRect] = Array(repeating: .zero, count: counts.image)
        var fileFrames: [NSRect] = Array(repeating: .zero, count: counts.file)
        var appShotFrames: [NSRect] = Array(repeating: .zero, count: counts.appShot)
        var currentY = contentInsets.top
        var maxRowWidth: CGFloat = 0

        for row in rows {
            for item in row.items {
                let frame = NSRect(
                    x: contentInsets.left + item.originX,
                    y: currentY + row.height - item.size.height,
                    width: item.size.width,
                    height: item.size.height
                )
                assignFrame(frame, for: item, imageFrames: &imageFrames, fileFrames: &fileFrames, appShotFrames: &appShotFrames)
            }
            maxRowWidth = max(maxRowWidth, row.width)
            currentY += row.height + BlockInputComposerStyle.imagePreviewInterItemSpacing
        }

        if !rows.isEmpty {
            currentY -= BlockInputComposerStyle.imagePreviewInterItemSpacing
        }
        let size = NSSize(
            width: contentInsets.left + maxRowWidth + contentInsets.right,
            height: currentY + contentInsets.bottom
        )
        return ComposerAttachmentStripLayoutPlan(
            size: size,
            imageFrames: imageFrames,
            fileFrames: fileFrames,
            appShotFrames: appShotFrames
        )
    }

    private func assignFrame(
        _ frame: NSRect,
        for item: ComposerAttachmentLayoutItem,
        imageFrames: inout [NSRect],
        fileFrames: inout [NSRect],
        appShotFrames: inout [NSRect]
    ) {
        switch item.kind {
        case .image(let index):
            imageFrames[index] = frame
        case .file(let index):
            fileFrames[index] = frame
        case .appShot(let index):
            appShotFrames[index] = frame
        }
    }

    private func appShotCardSize(for appShot: AppShotAttachment, constrainedTo maxWidth: CGFloat) -> NSSize {
        AppKitAppShotAttachmentCardView.fittingSize(
            for: imageSize(for: appShot.screenshot),
            maximumSize: NSSize(
                width: min(AppKitAppShotAttachmentCardView.composerMaximumSize.width, max(maxWidth, 1)),
                height: AppKitAppShotAttachmentCardView.composerMaximumSize.height
            )
        )
    }

    private func imageSize(for attachment: LocalImageAttachment) -> NSSize? {
        if let cached = imageSizeCache[attachment.id] {
            return cached == .zero ? nil : cached
        }
        guard let image = NSImage(contentsOf: attachment.fileURL),
              image.size.width > 0,
              image.size.height > 0 else {
            imageSizeCache[attachment.id] = .zero
            return nil
        }
        imageSizeCache[attachment.id] = image.size
        return image.size
    }

    private func apply(frames: [NSRect], to views: [NSView]) {
        for (index, view) in views.enumerated() {
            guard frames.indices.contains(index) else {
                view.frame = .zero
                continue
            }
            view.frame = frames[index]
        }
    }

}

private struct ComposerAttachmentStripLayoutPlan {
    let size: NSSize
    let imageFrames: [NSRect]
    let fileFrames: [NSRect]
    let appShotFrames: [NSRect]
}

private struct ComposerAttachmentLayoutRows {
    let rows: [ComposerAttachmentLayoutRow]
    let counts: ComposerAttachmentLayoutCounts
}

private struct ComposerAttachmentLayoutCounts {
    var image = 0
    var file = 0
    var appShot = 0
}

private struct ComposerAttachmentLayoutRow {
    let items: [ComposerAttachmentLayoutItem]
    let width: CGFloat
    let height: CGFloat
}

private struct ComposerAttachmentLayoutItem {
    let kind: ComposerAttachmentLayoutKind
    let size: NSSize
    let originX: CGFloat

    init(kind: ComposerAttachmentLayoutKind, size: NSSize, originX: CGFloat = 0) {
        self.kind = kind
        self.size = size
        self.originX = originX
    }

    func withOriginX(_ originX: CGFloat) -> ComposerAttachmentLayoutItem {
        ComposerAttachmentLayoutItem(kind: kind, size: size, originX: originX)
    }
}

private enum ComposerAttachmentLayoutKind {
    case image(Int)
    case file(Int)
    case appShot(Int)
}

#if DEBUG
extension AppKitComposerAttachmentStripView {
    var imageTileFramesForTesting: [CGRect] {
        imageTileViews.prefix(imageAttachments.count).map(\.frame)
    }

    var fileChipFramesForTesting: [CGRect] {
        fileChipViews.prefix(fileAttachments.count).map(\.frame)
    }

    var appShotCardFramesForTesting: [CGRect] {
        appShotCardViews.prefix(appShotAttachments.count).map(\.frame)
    }
}
#endif
