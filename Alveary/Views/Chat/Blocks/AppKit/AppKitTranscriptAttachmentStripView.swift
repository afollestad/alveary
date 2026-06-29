@preconcurrency import AppKit

@MainActor
final class AppKitTranscriptAttachmentStripView: NSView {
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

    static let appShotSectionSpacing: CGFloat = 8

    var appIconResolver: AppKitAppIconResolving = AppKitWorkspaceAppIconResolver.shared {
        didSet {
            appShotCardViews.forEach { $0.appIconResolver = appIconResolver }
        }
    }

    private var attachments: [TranscriptImageAttachment] = []
    private(set) var fileAttachments: [LocalFileAttachment] = []
    private(set) var tileViews: [AppKitImageAttachmentTileView] = []
    private(set) var fileChipViews: [AppKitFileAttachmentChipView] = []
    private(set) var appShotCardViews: [AppKitAppShotAttachmentCardView] = []
    private var alignment: Alignment = .leading
    private var imageSizeCache: [String: NSSize] = [:]
    var onOpenAttachment: ((TranscriptImageAttachment) -> Void)? {
        didSet {
            updateOpenHandlers()
        }
    }
    var onOpenFileAttachment: ((LocalFileAttachment) -> Void)? {
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

    func configure(
        _ attachments: [TranscriptImageAttachment],
        fileAttachments: [LocalFileAttachment] = [],
        alignment: Alignment = .leading
    ) {
        guard self.attachments != attachments || self.fileAttachments != fileAttachments || self.alignment != alignment else {
            return
        }
        self.attachments = attachments
        self.fileAttachments = fileAttachments
        self.alignment = alignment

        let plainAttachments = attachments.filter { !$0.isAppShot }.map(\.image)
        let appShotAttachments = attachments.compactMap(\.appShot)

        ensureTileViewCount(plainAttachments.count)
        ensureFileChipViewCount(fileAttachments.count)
        ensureAppShotCardViewCount(appShotAttachments.count)
        updateOpenHandlers()
        configureTileViews(plainAttachments)
        configureFileChipViews(fileAttachments)
        configureAppShotCardViews(appShotAttachments)
        needsLayout = true
    }

    func measuredSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        guard !attachments.isEmpty || !fileAttachments.isEmpty else {
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
        for (index, chipView) in fileChipViews.enumerated() {
            guard layoutPlan.fileChipFrames.indices.contains(index) else {
                chipView.frame = .zero
                continue
            }
            chipView.frame = layoutPlan.fileChipFrames[index]
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

    private func ensureTileViewCount(_ count: Int) {
        guard tileViews.count < count else {
            return
        }
        for _ in tileViews.count..<count {
            let tileView = AppKitImageAttachmentTileView()
            tileViews.append(tileView)
            addSubview(tileView)
        }
    }

    private func ensureFileChipViewCount(_ count: Int) {
        guard fileChipViews.count < count else {
            return
        }
        for _ in fileChipViews.count..<count {
            let chipView = AppKitFileAttachmentChipView()
            fileChipViews.append(chipView)
            addSubview(chipView)
        }
    }

    private func ensureAppShotCardViewCount(_ count: Int) {
        guard appShotCardViews.count < count else {
            return
        }
        for _ in appShotCardViews.count..<count {
            let cardView = AppKitAppShotAttachmentCardView()
            cardView.appIconResolver = appIconResolver
            appShotCardViews.append(cardView)
            addSubview(cardView)
        }
    }

    private func configureTileViews(_ plainAttachments: [LocalImageAttachment]) {
        for (index, tileView) in tileViews.enumerated() {
            guard plainAttachments.indices.contains(index) else {
                tileView.isHidden = true
                continue
            }
            tileView.configure(plainAttachments[index])
            tileView.isHidden = false
        }
    }

    private func configureFileChipViews(_ attachments: [LocalFileAttachment]) {
        for (index, chipView) in fileChipViews.enumerated() {
            guard attachments.indices.contains(index) else {
                chipView.isHidden = true
                continue
            }
            chipView.configure(attachments[index])
            chipView.isHidden = false
        }
    }

    private func configureAppShotCardViews(_ attachments: [PersistedAppShotAttachment]) {
        for (index, cardView) in appShotCardViews.enumerated() {
            guard attachments.indices.contains(index) else {
                cardView.isHidden = true
                continue
            }
            cardView.configure(attachments[index])
            cardView.isHidden = false
        }
    }

    private func layoutPlan(constrainedTo maxWidth: CGFloat) -> AttachmentStripLayoutPlan {
        let plainAttachments = plainAttachments
        let fileAttachments = fileAttachments
        let appShotAttachments = appShotAttachments
        let localLayout = localSectionLayout(
            imageCount: plainAttachments.count,
            fileCount: fileAttachments.count,
            constrainedTo: maxWidth
        )
        let appShotRows = appShotSectionRows(appShots: appShotAttachments, constrainedTo: maxWidth)
        let appShotWidth = appShotRows.map(\.width).max() ?? 0
        let appShotHeight = appShotRows.reduce(CGFloat(0)) { partialResult, row in
            partialResult + row.height
        } + CGFloat(max(appShotRows.count - 1, 0)) * Self.interItemSpacing
        let includesSectionSpacing = (!plainAttachments.isEmpty || !fileAttachments.isEmpty) && !appShotAttachments.isEmpty
        let width = max(localLayout.size.width, appShotWidth)
        var tileFrames = localLayout.tileFrames
        var fileChipFrames = localLayout.fileChipFrames
        if alignment == .trailing && width > localLayout.size.width {
            let xOffset = width - localLayout.size.width
            tileFrames = tileFrames.map { $0.offsetBy(dx: xOffset, dy: 0) }
            fileChipFrames = fileChipFrames.map { $0.offsetBy(dx: xOffset, dy: 0) }
        }
        let appShotOriginY = localLayout.size.height + (includesSectionSpacing ? Self.appShotSectionSpacing : 0)
        var appShotCardFrames: [NSRect] = []
        var currentY = appShotOriginY
        for row in appShotRows {
            let xOffset = alignment == .trailing ? width - row.width : 0
            for card in row.cards {
                appShotCardFrames.append(card.frame.offsetBy(dx: xOffset, dy: currentY))
            }
            currentY += row.height + Self.interItemSpacing
        }
        let height = localLayout.size.height +
            (includesSectionSpacing ? Self.appShotSectionSpacing : 0) +
            appShotHeight
        return AttachmentStripLayoutPlan(
            size: NSSize(width: width, height: height),
            tileFrames: tileFrames,
            fileChipFrames: fileChipFrames,
            appShotCardFrames: appShotCardFrames
        )
    }

    private func localSectionLayout(
        imageCount: Int,
        fileCount: Int,
        constrainedTo maxWidth: CGFloat
    ) -> LocalAttachmentLayout {
        guard imageCount > 0 || fileCount > 0 else {
            return LocalAttachmentLayout(size: .zero, tileFrames: [], fileChipFrames: [])
        }
        let effectiveMaxWidth = max(maxWidth, 1)
        var accumulator = LocalAttachmentLayoutAccumulator(effectiveMaxWidth: effectiveMaxWidth, spacing: Self.interItemSpacing)
        for imageIndex in 0..<imageCount {
            accumulator.append(
                .image(imageIndex),
                size: Self.thumbnailSize,
            )
        }
        for fileIndex in 0..<fileCount {
            accumulator.append(
                .file(fileIndex),
                size: fileChipSize(constrainedTo: effectiveMaxWidth),
            )
        }
        return localAttachmentLayout(from: accumulator.finish(), imageCount: imageCount, fileCount: fileCount)
    }

    private func localAttachmentLayout(
        from rows: [LocalAttachmentLayoutRow],
        imageCount: Int,
        fileCount: Int
    ) -> LocalAttachmentLayout {
        var tileFrames = Array(repeating: NSRect.zero, count: imageCount)
        var fileChipFrames = Array(repeating: NSRect.zero, count: fileCount)
        var currentY: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for row in rows {
            for item in row.items {
                let frame = item.frame.offsetBy(dx: 0, dy: currentY)
                switch item.kind {
                case .image(let index):
                    tileFrames[index] = frame
                case .file(let index):
                    fileChipFrames[index] = frame
                }
            }
            maxRowWidth = max(maxRowWidth, row.width)
            currentY += row.height + Self.interItemSpacing
        }
        if !rows.isEmpty {
            currentY -= Self.interItemSpacing
        }
        return LocalAttachmentLayout(
            size: NSSize(width: maxRowWidth, height: currentY),
            tileFrames: tileFrames,
            fileChipFrames: fileChipFrames
        )
    }

    private func fileChipSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        NSSize(
            width: min(AppKitFileAttachmentChipView.preferredSize.width, max(maxWidth, 1)),
            height: AppKitFileAttachmentChipView.preferredSize.height
        )
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
        AppKitAppShotAttachmentCardView.fittingSize(
            for: imageSize(for: appShot.screenshot),
            maximumSize: NSSize(
                width: min(AppKitAppShotAttachmentCardView.transcriptMaximumSize.width, max(maxWidth, 1)),
                height: AppKitAppShotAttachmentCardView.transcriptMaximumSize.height
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

    private func updateOpenHandlers() {
        guard onOpenAttachment != nil || onOpenFileAttachment != nil else {
            tileViews.forEach { $0.onOpenAttachment = nil }
            fileChipViews.forEach { chipView in
                chipView.onOpenAttachment = nil
                chipView.onRemoveAttachment = nil
            }
            appShotCardViews.forEach { $0.onOpenAttachment = nil }
            return
        }
        tileViews.forEach { tileView in
            if onOpenAttachment == nil {
                tileView.onOpenAttachment = nil
            } else {
                tileView.onOpenAttachment = { [weak self] attachment in
                    self?.onOpenAttachment?(TranscriptImageAttachment(localImageAttachment: attachment))
                }
            }
        }
        fileChipViews.forEach { chipView in
            if onOpenFileAttachment == nil {
                chipView.onOpenAttachment = nil
            } else {
                chipView.onOpenAttachment = { [weak self] attachment in
                    self?.onOpenFileAttachment?(attachment)
                }
            }
            chipView.onRemoveAttachment = nil
        }
        appShotCardViews.forEach { cardView in
            if onOpenAttachment == nil {
                cardView.onOpenAttachment = nil
            } else {
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
}

private struct AttachmentStripLayoutPlan {
    let size: NSSize
    let tileFrames: [NSRect]
    let fileChipFrames: [NSRect]
    let appShotCardFrames: [NSRect]
}

private struct LocalAttachmentLayout {
    let size: NSSize
    let tileFrames: [NSRect]
    let fileChipFrames: [NSRect]
}

private struct LocalAttachmentLayoutRow {
    let items: [LocalAttachmentLayoutItem]
    let width: CGFloat
    let height: CGFloat
}

private struct LocalAttachmentLayoutItem {
    let kind: LocalAttachmentLayoutKind
    let frame: NSRect
}

private enum LocalAttachmentLayoutKind {
    case image(Int)
    case file(Int)
}

private struct LocalAttachmentLayoutAccumulator {
    let effectiveMaxWidth: CGFloat
    let spacing: CGFloat
    private var rows: [LocalAttachmentLayoutRow] = []
    private var currentItems: [LocalAttachmentLayoutItem] = []
    private var currentWidth: CGFloat = 0
    private var currentHeight: CGFloat = 0

    mutating func append(_ kind: LocalAttachmentLayoutKind, size: NSSize) {
        let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
        if !currentItems.isEmpty && nextWidth > effectiveMaxWidth {
            appendCurrentRow()
        }
        let itemX = currentItems.isEmpty ? 0 : currentWidth + spacing
        currentItems.append(LocalAttachmentLayoutItem(
            kind: kind,
            frame: NSRect(x: itemX, y: 0, width: size.width, height: size.height)
        ))
        currentWidth = itemX + size.width
        currentHeight = max(currentHeight, size.height)
    }

    mutating func finish() -> [LocalAttachmentLayoutRow] {
        appendCurrentRow()
        return rows
    }

    private mutating func appendCurrentRow() {
        guard !currentItems.isEmpty else {
            return
        }
        let rowItems = currentItems.map { item in
            LocalAttachmentLayoutItem(kind: item.kind, frame: item.frame.offsetBy(dx: 0, dy: currentHeight - item.frame.height))
        }
        rows.append(LocalAttachmentLayoutRow(items: rowItems, width: currentWidth, height: currentHeight))
        currentItems = []
        currentWidth = 0
        currentHeight = 0
    }
}

private struct AppShotLayoutRow {
    let cards: [AppShotLayoutCard]
    let width: CGFloat
    let height: CGFloat
}

private struct AppShotLayoutCard {
    let frame: NSRect
}
