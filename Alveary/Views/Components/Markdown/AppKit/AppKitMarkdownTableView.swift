@preconcurrency import AppKit
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
        CGFloat(columnCount) * minimumColumnWidth
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
        return min(naturalWidth, fallbackTableViewportWidth)
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
    private var textView: AppKitMarkdownTextView?

    init(
        content: AttributedString,
        isHeader: Bool,
        alignment: NSTextAlignment,
        rendering: AppKitMarkdownTableRendering
    ) {
        self.isHeader = isHeader
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    override func layout() {
        super.layout()
        textView?.frame = bounds.insetBy(dx: 10, dy: 7)
        textView?.layoutSubtreeIfNeeded()
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        textView?.frame = NSRect(x: 10, y: 7, width: max(width - 20, 0), height: CGFloat.greatestFiniteMagnitude / 2)
        textView?.layoutSubtreeIfNeeded()
        return ceil((textView?.intrinsicContentSize.height ?? 0) + 14)
    }

    private func setup(
        content: AttributedString,
        alignment: NSTextAlignment,
        rendering: AppKitMarkdownTableRendering
    ) {
        wantsLayer = true
        layer?.borderWidth = 0.5
        updateLayerColors()

        let textView = AppKitMarkdownTextView(
            content: AppKitMarkdownAttributedStringBuilder.attributedString(
                from: content,
                baseFont: rendering.typography.body,
                inlineCodeFont: rendering.typography.inlineCode,
                weight: isHeader ? .semibold : .regular,
                inlineCodeStyle: rendering.inlineCodeStyle
            ),
            onOpenLink: rendering.onOpenLink,
            heightInvalidationHandler: rendering.heightInvalidationHandler
        )
        textView.alignment = alignment
        textView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(textView)
        self.textView = textView
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

private let minimumColumnWidth: CGFloat = 120
private let fallbackTableViewportWidth: CGFloat = 520
