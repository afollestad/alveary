@preconcurrency import AppKit

@MainActor
final class AppKitTranscriptImageAttachmentStripView: NSView {
    enum Alignment: Equatable {
        case leading
        case trailing
    }

    static var thumbnailSize: NSSize {
        BlockInputComposerStyle.imagePreviewThumbnailSize
    }

    static var interItemSpacing: CGFloat {
        BlockInputComposerStyle.imagePreviewInterItemSpacing
    }

    static let appShotCardMaxSize = NSSize(width: 220, height: 160)
    static let appShotCardFallbackSize = NSSize(width: 220, height: 140)
    static let appShotSectionSpacing: CGFloat = 8

    var appIconResolver: AppKitAppIconResolving = AppKitWorkspaceAppIconResolver.shared {
        didSet {
            appShotCardViews.forEach { $0.appIconResolver = appIconResolver }
        }
    }

    private var attachments: [TranscriptImageAttachment] = []
    private(set) var tileViews: [AppKitImageAttachmentTileView] = []
    private(set) var appShotCardViews: [AppKitAppShotAttachmentCardView] = []
    private var alignment: Alignment = .leading
    private var imageSizeCache: [String: NSSize] = [:]
    var onOpenAttachment: ((TranscriptImageAttachment) -> Void)? {
        didSet {
            updateOpenHandlers()
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

    func configure(_ attachments: [TranscriptImageAttachment], alignment: Alignment = .leading) {
        guard self.attachments != attachments || self.alignment != alignment else {
            return
        }
        self.attachments = attachments
        self.alignment = alignment

        let plainAttachments = attachments.filter { !$0.isAppShot }.map(\.image)
        let appShotAttachments = attachments.compactMap(\.appShot)

        if tileViews.count < plainAttachments.count {
            for _ in tileViews.count..<plainAttachments.count {
                let tileView = AppKitImageAttachmentTileView()
                tileViews.append(tileView)
                addSubview(tileView)
            }
        }
        if appShotCardViews.count < appShotAttachments.count {
            for _ in appShotCardViews.count..<appShotAttachments.count {
                let cardView = AppKitAppShotAttachmentCardView()
                cardView.appIconResolver = appIconResolver
                appShotCardViews.append(cardView)
                addSubview(cardView)
            }
        }
        updateOpenHandlers()

        for (index, tileView) in tileViews.enumerated() {
            if plainAttachments.indices.contains(index) {
                tileView.configure(plainAttachments[index])
                tileView.isHidden = false
            } else {
                tileView.isHidden = true
            }
        }
        for (index, cardView) in appShotCardViews.enumerated() {
            if appShotAttachments.indices.contains(index) {
                cardView.configure(appShotAttachments[index])
                cardView.isHidden = false
            } else {
                cardView.isHidden = true
            }
        }
        needsLayout = true
    }

    func measuredSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        guard !attachments.isEmpty else {
            return .zero
        }
        return layoutPlan(constrainedTo: maxWidth).size
    }

    override func layout() {
        super.layout()
        let layoutPlan = layoutPlan(constrainedTo: bounds.width)
        for (index, tileView) in tileViews.enumerated() {
            guard layoutPlan.tileFrames.indices.contains(index) else {
                tileView.frame = .zero
                continue
            }
            tileView.frame = layoutPlan.tileFrames[index]
        }
        for (index, cardView) in appShotCardViews.enumerated() {
            guard layoutPlan.appShotCardFrames.indices.contains(index) else {
                cardView.frame = .zero
                continue
            }
            cardView.frame = layoutPlan.appShotCardFrames[index]
        }
    }

    var plainAttachments: [LocalImageAttachment] {
        attachments.filter { !$0.isAppShot }.map(\.image)
    }

    var appShotAttachments: [PersistedAppShotAttachment] {
        attachments.compactMap(\.appShot)
    }

    private func layoutPlan(constrainedTo maxWidth: CGFloat) -> AttachmentStripLayoutPlan {
        let plainAttachments = plainAttachments
        let appShotAttachments = appShotAttachments
        let plainLayout = plainSectionLayout(attachmentCount: plainAttachments.count, constrainedTo: maxWidth)
        let appShotRows = appShotSectionRows(appShots: appShotAttachments, constrainedTo: maxWidth)
        let appShotWidth = appShotRows.map(\.width).max() ?? 0
        let appShotHeight = appShotRows.reduce(CGFloat(0)) { partialResult, row in
            partialResult + row.height
        } + CGFloat(max(appShotRows.count - 1, 0)) * Self.interItemSpacing
        let includesSectionSpacing = !plainAttachments.isEmpty && !appShotAttachments.isEmpty
        let width = max(plainLayout.size.width, appShotWidth)
        var tileFrames = plainLayout.frames
        if alignment == .trailing && width > plainLayout.size.width {
            let xOffset = width - plainLayout.size.width
            tileFrames = tileFrames.map { $0.offsetBy(dx: xOffset, dy: 0) }
        }
        let appShotOriginY = plainLayout.size.height + (includesSectionSpacing ? Self.appShotSectionSpacing : 0)
        var appShotCardFrames: [NSRect] = []
        var currentY = appShotOriginY
        for row in appShotRows {
            let xOffset = alignment == .trailing ? width - row.width : 0
            for card in row.cards {
                appShotCardFrames.append(card.frame.offsetBy(dx: xOffset, dy: currentY))
            }
            currentY += row.height + Self.interItemSpacing
        }
        let height = plainLayout.size.height +
            (includesSectionSpacing ? Self.appShotSectionSpacing : 0) +
            appShotHeight
        return AttachmentStripLayoutPlan(
            size: NSSize(width: width, height: height),
            tileFrames: tileFrames,
            appShotCardFrames: appShotCardFrames
        )
    }

    private func plainSectionLayout(attachmentCount: Int, constrainedTo maxWidth: CGFloat) -> (size: NSSize, frames: [NSRect]) {
        guard attachmentCount > 0 else {
            return (.zero, [])
        }
        let columnCount = plainColumnCount(constrainedTo: maxWidth)
        let visibleColumnCount = min(columnCount, attachmentCount)
        let rowCount = Int(ceil(Double(attachmentCount) / Double(columnCount)))
        let size = NSSize(
            width: CGFloat(visibleColumnCount) * Self.thumbnailSize.width +
                CGFloat(max(visibleColumnCount - 1, 0)) * Self.interItemSpacing,
            height: CGFloat(rowCount) * Self.thumbnailSize.height +
                CGFloat(max(rowCount - 1, 0)) * Self.interItemSpacing
        )
        let frames = (0..<attachmentCount).map { index in
            let column = index % columnCount
            let row = index / columnCount
            return NSRect(
                x: CGFloat(column) * (Self.thumbnailSize.width + Self.interItemSpacing),
                y: CGFloat(row) * (Self.thumbnailSize.height + Self.interItemSpacing),
                width: Self.thumbnailSize.width,
                height: Self.thumbnailSize.height
            )
        }
        return (size, frames)
    }

    private func appShotSectionRows(
        appShots: [PersistedAppShotAttachment],
        constrainedTo maxWidth: CGFloat
    ) -> [AppShotLayoutRow] {
        guard !appShots.isEmpty else {
            return []
        }
        let effectiveMaxWidth = max(maxWidth, 1)
        var rows: [AppShotLayoutRow] = []
        var currentCards: [AppShotLayoutCard] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        for appShot in appShots {
            let size = appShotCardSize(for: appShot, constrainedTo: effectiveMaxWidth)
            let nextWidth = currentCards.isEmpty ? size.width : currentWidth + Self.interItemSpacing + size.width
            if !currentCards.isEmpty && nextWidth > effectiveMaxWidth {
                rows.append(AppShotLayoutRow(cards: currentCards, width: currentWidth, height: currentHeight))
                currentCards = []
                currentWidth = 0
                currentHeight = 0
            }
            let cardX = currentCards.isEmpty ? 0 : currentWidth + Self.interItemSpacing
            currentCards.append(AppShotLayoutCard(frame: NSRect(origin: NSPoint(x: cardX, y: 0), size: size)))
            currentWidth = cardX + size.width
            currentHeight = max(currentHeight, size.height)
        }
        if !currentCards.isEmpty {
            rows.append(AppShotLayoutRow(cards: currentCards, width: currentWidth, height: currentHeight))
        }
        return rows
    }

    private func appShotCardSize(for appShot: PersistedAppShotAttachment, constrainedTo maxWidth: CGFloat) -> NSSize {
        let sourceSize = imageSize(for: appShot.screenshot) ?? Self.appShotCardFallbackSize
        let maxWidth = min(Self.appShotCardMaxSize.width, max(maxWidth, 1))
        let maxHeight = Self.appShotCardMaxSize.height
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return Self.appShotCardFallbackSize
        }
        let scale = min(maxWidth / sourceSize.width, maxHeight / sourceSize.height)
        return NSSize(
            width: max(floor(sourceSize.width * scale), 1),
            height: max(floor(sourceSize.height * scale), 1)
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

    private func plainColumnCount(constrainedTo maxWidth: CGFloat) -> Int {
        let effectiveMaxWidth = max(maxWidth, Self.thumbnailSize.width)
        return max(
            1,
            Int(floor((effectiveMaxWidth + Self.interItemSpacing) / (Self.thumbnailSize.width + Self.interItemSpacing)))
        )
    }

    private func updateOpenHandlers() {
        guard onOpenAttachment != nil else {
            tileViews.forEach { $0.onOpenAttachment = nil }
            appShotCardViews.forEach { $0.onOpenAttachment = nil }
            return
        }
        tileViews.forEach { tileView in
            tileView.onOpenAttachment = { [weak self] attachment in
                self?.onOpenAttachment?(TranscriptImageAttachment(localImageAttachment: attachment))
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
                self.onOpenAttachment?(TranscriptImageAttachment(appShot: self.appShotAttachments[index]))
            }
        }
    }
}

private struct AttachmentStripLayoutPlan {
    let size: NSSize
    let tileFrames: [NSRect]
    let appShotCardFrames: [NSRect]
}

private struct AppShotLayoutRow {
    let cards: [AppShotLayoutCard]
    let width: CGFloat
    let height: CGFloat
}

private struct AppShotLayoutCard {
    let frame: NSRect
}
