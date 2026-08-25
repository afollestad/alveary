@preconcurrency import AppKit
import BlockInputKit
import Foundation

/// AppKit table renderer that keeps the visible viewport sized to the bubble
/// while allowing the table document to overflow horizontally inside it.
final class AppKitMarkdownTableView: AppKitDynamicColorView {
    // Transcript measurement may temporarily stretch this outer view; keep
    // rounded table chrome on a content-height child so blank space stays clear.
    private let chromeView = AppKitFlippedDynamicColorView()
    private let scrollView = AppKitHorizontalOverflowScrollView()
    private let documentView = AppKitMarkdownTableDocumentView()
    private var cellRows: [[AppKitMarkdownTableCellView]] = []
    private var columnCount = 0
    private var hasAppliedInitialScrollPosition = false

    init(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        columns: [PresentationIntent.TableColumn],
        rendering: AppKitMarkdownTableRendering
    ) {
        super.init(frame: .zero)
        setup(
            rows: Self.rows(intent: intent, content: content),
            columns: columns,
            rendering: rendering
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: totalHeight(for: bounds.width))
    }

    override var fittingSize: NSSize {
        NSSize(width: viewportWidth(for: bounds.width), height: totalHeight(for: bounds.width))
    }

    func naturalViewportWidth(constrainedTo maxWidth: CGFloat) -> CGFloat {
        min(naturalTableWidth, max(maxWidth, 0))
    }

    override func layout() {
        super.layout()
        layoutCells()
        if !hasAppliedInitialScrollPosition {
            // Normalize the first render, then leave the clip-view origin alone.
            // Transcript relayouts can run after a user horizontally scrolls a
            // wide table, and sizing the document must not yank that local table
            // scroll position back to the leading edge.
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hasAppliedInitialScrollPosition = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func setup(
        rows: [[AttributedString]],
        columns: [PresentationIntent.TableColumn],
        rendering: AppKitMarkdownTableRendering
    ) {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        chromeView.wantsLayer = true
        chromeView.layer?.cornerRadius = markdownTableCornerRadius
        chromeView.layer?.cornerCurve = .continuous
        chromeView.layer?.masksToBounds = true
        chromeView.layer?.borderWidth = 1
        chromeView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(chromeView)
        updateLayerColors()

        columnCount = max(columns.count, rows.map(\.count).max() ?? 0)
        cellRows = rows.enumerated().map { rowIndex, row in
            (0..<columnCount).map { columnIndex in
                let cell = AppKitMarkdownTableCellView(
                    content: row[safe: columnIndex] ?? AttributedString(),
                    isHeader: rowIndex == 0,
                    alignment: Self.alignment(for: columnIndex, columns: columns),
                    rendering: rendering
                )
                documentView.addSubview(cell)
                return cell
            }
        }

        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        chromeView.addSubview(scrollView)
    }

    private func updateLayerColors() {
        chromeView.setLayerFillColor(alpha: 0.45, provider: { AppMarkdownCodeBlockPalette.fillNSColor(for: $0) })
        chromeView.setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
    }

    private func layoutCells() {
        guard columnCount > 0 else {
            chromeView.frame = .zero
            scrollView.frame = .zero
            documentView.frame = .zero
            return
        }
        let tableWidth = tableDocumentWidth(for: bounds.width)
        let columnWidth = tableWidth / CGFloat(columnCount)
        var currentY: CGFloat = 0
        for row in cellRows {
            let rowHeight = row.map { $0.measuredHeight(width: columnWidth) }.max() ?? 0
            for (columnIndex, cell) in row.enumerated() {
                cell.frame = NSRect(
                    x: CGFloat(columnIndex) * columnWidth,
                    y: currentY,
                    width: columnWidth,
                    height: rowHeight
                )
                cell.layoutSubtreeIfNeeded()
            }
            currentY += rowHeight
        }
        let viewportWidth = viewportWidth(for: bounds.width)
        chromeView.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: currentY + horizontalScrollbarReserve(for: bounds.width))
        scrollView.frame = chromeView.bounds
        documentView.frame = NSRect(x: 0, y: 0, width: tableWidth, height: currentY)
        scrollView.clampHorizontalScrollOffset()
    }

    private func tableSize(for width: CGFloat) -> NSSize {
        guard columnCount > 0 else {
            return .zero
        }
        // Long transcript tables should expose horizontal overflow only when the
        // table has too many columns to fit. Narrow tables keep their natural
        // width even when the surrounding bubble can offer more room.
        let tableWidth = tableDocumentWidth(for: width)
        let columnWidth = tableWidth / CGFloat(columnCount)
        let height = cellRows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + (row.map { $0.measuredHeight(width: columnWidth) }.max() ?? 0)
        }
        return NSSize(width: tableWidth, height: height)
    }

    private var naturalTableWidth: CGFloat {
        CGFloat(columnCount) * columnWidthFloor
    }

    /// The per-column width floor. An image cell needs the room its capped bitmap occupies, and
    /// every column here is equal-width, so the widest image cell raises the floor for all of them
    /// rather than being squeezed into `AppKitMarkdownTableMetrics.minimumColumnWidth`. Computed
    /// rather than stored: a remote image's real dimensions resolve after the table is built.
    private var columnWidthFloor: CGFloat {
        cellRows.lazy.joined().reduce(AppKitMarkdownTableMetrics.minimumColumnWidth) { floor, cell in
            max(floor, cell.naturalContentWidth)
        }
    }

    private func tableDocumentWidth(for width: CGFloat) -> CGFloat {
        max(naturalTableWidth, viewportWidth(for: width))
    }

    private func totalHeight(for width: CGFloat) -> CGFloat {
        let tableSize = tableSize(for: width)
        return tableSize.height + horizontalScrollbarReserve(for: width, tableWidth: tableSize.width)
    }

    private func horizontalScrollbarReserve(for width: CGFloat) -> CGFloat {
        horizontalScrollbarReserve(for: width, tableWidth: tableSize(for: width).width)
    }

    private func horizontalScrollbarReserve(for width: CGFloat, tableWidth: CGFloat) -> CGFloat {
        guard tableWidth > viewportWidth(for: width) + 0.5 else {
            return 0
        }
        return ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay))
    }

    private func viewportWidth(for width: CGFloat) -> CGFloat {
        guard columnCount > 0 else {
            return 0
        }
        let naturalWidth = naturalTableWidth
        if width > 0 {
            return min(naturalWidth, width)
        }
        return min(naturalWidth, AppKitMarkdownTableMetrics.fallbackViewportWidth)
    }

    private static func rows(
        intent: PresentationIntent.IntentType?,
        content: AttributedString
    ) -> [[AttributedString]] {
        content.appMarkdownBlockRuns(parent: intent).compactMap { rowRun in
            let rowContent = content[rowRun.range]
            let cells = rowContent.appMarkdownBlockRuns(parent: rowRun.intent).map { cellRun in
                AttributedString(rowContent[cellRun.range])
            }
            return isDelimiterRow(cells) ? nil : cells
        }
    }

    private static func isDelimiterRow(_ cells: [AttributedString]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            let text = String(cell.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private static func alignment(
        for columnIndex: Int,
        columns: [PresentationIntent.TableColumn]
    ) -> NSTextAlignment {
        guard columnIndex < columns.count else {
            return .left
        }
        switch columns[columnIndex].alignment {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        @unknown default:
            return .left
        }
    }
}

private final class AppKitMarkdownTableCellView: AppKitDynamicColorView {
    private let isHeader: Bool
    private let alignment: NSTextAlignment
    private var textView: AppKitMarkdownTextView?
    /// Set instead of `textView` when the cell holds nothing but an image, so the bitmap fits the
    /// column the way GitHub renders it rather than sizing against the text run.
    private var imageView: AppKitMarkdownImageBlockView?
    /// Set alongside `imageView` so the capped box can be re-resolved after a load lands.
    private var cellImage: AppMarkdownCellImage?
    private var imageStore: AppMarkdownImageStore?

    init(
        content: AttributedString,
        isHeader: Bool,
        alignment: NSTextAlignment,
        rendering: AppKitMarkdownTableRendering
    ) {
        self.isHeader = isHeader
        self.alignment = alignment
        super.init(frame: .zero)
        setup(
            content: content,
            alignment: alignment,
            rendering: rendering
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// What this cell needs its column to be at least as wide as, chrome included. Only an image
    /// cell has an opinion; a text cell wraps into whatever column width it is given.
    var naturalContentWidth: CGFloat {
        // Deliberately the store-derived cap rather than the view's current size: the view's is
        // already clamped by the column it was given, which would let a narrow column keep itself
        // narrow forever.
        guard imageView != nil else {
            return 0
        }
        return cappedImageWidth + AppKitMarkdownTableMetrics.cellHorizontalPadding * 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    override func layout() {
        super.layout()
        if let imageView {
            // Sized here rather than read back from the view: its own sizing clamps to its current
            // bounds, so a column that grew would never let the image grow with it.
            let size = imageDisplaySize(inCellWidth: bounds.width)
            imageView.maximumDisplayWidth = size.width
            imageView.frame = NSRect(
                x: imageOriginX(forImageWidth: size.width, cellWidth: bounds.width),
                y: AppKitMarkdownTableMetrics.cellVerticalPadding,
                width: size.width,
                height: size.height
            )
            imageView.layoutSubtreeIfNeeded()
            return
        }
        textView?.frame = bounds.insetBy(
            dx: AppKitMarkdownTableMetrics.cellHorizontalPadding,
            dy: AppKitMarkdownTableMetrics.cellVerticalPadding
        )
        textView?.layoutSubtreeIfNeeded()
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if imageView != nil {
            return ceil(
                imageDisplaySize(inCellWidth: width).height + AppKitMarkdownTableMetrics.cellVerticalPadding * 2
            )
        }
        textView?.frame = NSRect(
            x: AppKitMarkdownTableMetrics.cellHorizontalPadding,
            y: AppKitMarkdownTableMetrics.cellVerticalPadding,
            width: max(width - AppKitMarkdownTableMetrics.cellHorizontalPadding * 2, 0),
            height: CGFloat.greatestFiniteMagnitude / 2
        )
        textView?.layoutSubtreeIfNeeded()
        return ceil((textView?.intrinsicContentSize.height ?? 0) + AppKitMarkdownTableMetrics.cellVerticalPadding * 2)
    }

    private func setup(
        content: AttributedString,
        alignment: NSTextAlignment,
        rendering: AppKitMarkdownTableRendering
    ) {
        wantsLayer = true
        layer?.borderWidth = 0.5
        updateLayerColors()

        if let cellImage = content.appMarkdownSoleInlineImage {
            setupImage(cellImage, rendering: rendering)
            return
        }

        let textView = AppKitMarkdownTextView(
            content: AppKitMarkdownAttributedStringBuilder.attributedString(
                from: content,
                baseFont: rendering.typography.body,
                inlineCodeFont: rendering.typography.inlineCode,
                weight: isHeader ? .semibold : .regular,
                inlineCodeStyle: rendering.inlineCodeStyle,
                imageStore: rendering.imageStore
            ),
            onOpenLink: rendering.onOpenLink,
            heightInvalidationHandler: rendering.heightInvalidationHandler
        )
        textView.alignment = alignment
        textView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(textView)
        self.textView = textView
    }

    private func setupImage(
        _ cellImage: AppMarkdownCellImage,
        rendering: AppKitMarkdownTableRendering
    ) {
        let onOpenLink = rendering.onOpenLink
        let imageView = AppKitMarkdownImageBlockView(
            configuration: .init(image: cellImage.image, baseURL: nil),
            imageStore: rendering.imageStore,
            onOpen: { image, _ in
                // The wrapper link is what the author pointed the thumbnail at; without one the
                // image's own source is the only thing left to open.
                guard let url = cellImage.link
                    ?? AppMarkdownImageSourceResolver.resolvedURL(for: image.source, baseURL: nil) else {
                    return
                }
                onOpenLink?(url)
            },
            onHeightInvalidated: rendering.heightInvalidationHandler
        )
        self.cellImage = cellImage
        imageStore = rendering.imageStore
        imageView.maximumDisplayWidth = AppKitMarkdownTableMetrics
            .imageDisplaySize(for: cellImage, store: rendering.imageStore)
            .width
        imageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(imageView)
        self.imageView = imageView
    }

    /// The cap this cell's image asks its column to clear, before the column has a width to offer.
    private var cappedImageWidth: CGFloat {
        guard let cellImage, let imageStore else {
            return 0
        }
        return AppKitMarkdownTableMetrics.imageDisplaySize(for: cellImage, store: imageStore).width
    }

    private func imageDisplaySize(inCellWidth cellWidth: CGFloat) -> CGSize {
        guard let cellImage, let imageStore else {
            return .zero
        }
        return AppKitMarkdownTableMetrics.imageDisplaySize(
            for: cellImage,
            store: imageStore,
            inCellWidth: cellWidth
        )
    }

    private func imageOriginX(forImageWidth imageWidth: CGFloat, cellWidth: CGFloat) -> CGFloat {
        let padding = AppKitMarkdownTableMetrics.cellHorizontalPadding
        let interior = max(cellWidth - padding * 2, 0)
        switch alignment {
        case .center:
            return padding + max(0, (interior - imageWidth) / 2)
        case .right:
            return padding + max(0, interior - imageWidth)
        default:
            return padding
        }
    }

    private func updateLayerColors() {
        setLayerFillColor(isHeader ? .separatorColor : nil, alpha: isHeader ? 0.08 : 1)
        setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
    }
}

private final class AppKitMarkdownTableDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

struct AppKitMarkdownTableRendering {
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let typography: AppKitMarkdownTypography
    let onOpenLink: ((URL) -> Void)?
    let heightInvalidationHandler: () -> Void
    let imageStore: AppMarkdownImageStore
}

#if DEBUG
extension AppKitMarkdownTableView {
    var tableChromeFrameForTesting: NSRect {
        chromeView.frame
    }

    var tableDocumentFrameForTesting: NSRect {
        documentView.frame
    }

    var tableCornerRadiusForTesting: CGFloat {
        chromeView.layer?.cornerRadius ?? 0
    }

    var tableBorderColorForTesting: CGColor? {
        chromeView.layer?.borderColor
    }

    var tableCellBorderColorsForTesting: [CGColor?] {
        cellRows.flatMap { row in
            row.map { $0.layer?.borderColor }
        }
    }
}
#endif

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
