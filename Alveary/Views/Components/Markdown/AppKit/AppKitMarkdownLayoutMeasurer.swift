@preconcurrency import AppKit
import Foundation
import SwiftUI

private let tableMinimumColumnWidth: CGFloat = 120
private let tableFallbackViewportWidth: CGFloat = 520
private let tableCellHorizontalPadding: CGFloat = 10
private let tableCellVerticalPadding: CGFloat = 7
private let codeBlockHorizontalInset: CGFloat = 12
private let codeBlockVerticalInset: CGFloat = 10
// AppKit's scroll-view-backed code block fitting keeps short code surfaces from
// collapsing to the raw glyph width; preserve that natural bubble width here.
private let codeBlockMinimumNaturalWidth: CGFloat = 310

/// Exact layout preparation for AppKit markdown that mirrors
/// `AppKitMarkdownView` without constructing an `NSView` tree.
@MainActor
struct AppKitMarkdownLayoutMeasurer {
    let document: AppMarkdownDocument
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let typography: AppKitMarkdownTypography
    let colorScheme: ColorScheme
    // Must match the renderer's store or inline attachment swaps and image
    // blocks measure a different height than they draw.
    let imageStore: AppMarkdownImageStore
    // Must match `AppKitMarkdownView.imageBaseURL`, or a relative image source
    // resolves to a file here and to nothing in the renderer.
    let imageBaseURL: URL?

    init(
        document: AppMarkdownDocument,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        typography: AppKitMarkdownTypography = .default,
        colorScheme: ColorScheme = .light,
        imageStore: AppMarkdownImageStore = .shared,
        imageBaseURL: URL? = nil
    ) {
        self.document = document
        self.inlineCodeStyle = inlineCodeStyle
        self.typography = typography
        self.colorScheme = colorScheme
        self.imageStore = imageStore
        self.imageBaseURL = imageBaseURL
    }

    func measure(width: CGFloat) -> AppKitMarkdownLayoutMeasurement {
        measureBlocks(
            document.blocks,
            width: max(width, 0),
            path: ""
        )
    }

    private func measureBlocks(
        _ blocks: [AppMarkdownDocumentBlock],
        width: CGFloat,
        path: String
    ) -> AppKitMarkdownLayoutMeasurement {
        let measurements = blocks.enumerated().map { index, block in
            switch block {
            case .markdown(let content):
                return measureBlocks(
                    content,
                    parent: nil,
                    width: width,
                    path: path.appMarkdownAppendingPathComponent(index)
                )
            case .image(let imageBlock):
                return measureImage(imageBlock.image, width: width)
            case .details(let detailsBlock):
                return measureDetails(
                    detailsBlock,
                    width: width,
                    path: path.appMarkdownAppendingPathComponent(index)
                )
            }
        }
        let spacing = AppKitMarkdownMetrics.blockSpacing * CGFloat(max(measurements.count - 1, 0))
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(measurements.map(\.contentHeight).reduce(0, +) + spacing),
            naturalContentWidth: ceil(measurements.map(\.naturalContentWidth).max() ?? 0),
            fallbackRequired: measurements.contains(where: \.fallbackRequired)
        )
    }

    private func measureBlocks(
        _ content: AttributedString,
        parent: PresentationIntent.IntentType?,
        width: CGFloat,
        path: String
    ) -> AppKitMarkdownLayoutMeasurement {
        let runs = content.appMarkdownBlockRuns(parent: parent)
        let blocks = runs.enumerated().map { index, run in
            measureBlock(
                run: run,
                content: AttributedString(content[run.range]),
                parent: parent,
                width: width,
                path: path.appMarkdownAppendingPathComponent(index)
            )
        }
        let spacing = AppKitMarkdownMetrics.blockSpacing * CGFloat(max(blocks.count - 1, 0))
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(blocks.map(\.contentHeight).reduce(0, +) + spacing),
            naturalContentWidth: ceil(blocks.map(\.naturalContentWidth).max() ?? 0),
            fallbackRequired: false
        )
    }

    private func measureBlock(
        run: AppMarkdownBlockRun,
        content: AttributedString,
        parent: PresentationIntent.IntentType?,
        width: CGFloat,
        path: String
    ) -> AppKitMarkdownLayoutMeasurement {
        switch run.intent?.kind {
        case .header(let level):
            return measureText(content, font: typography.headingFont(for: level), weight: .semibold, width: width)
        case .codeBlock(let languageHint):
            return measureCodeBlock(content, languageHint: languageHint, width: width)
        case .unorderedList:
            return measureList(intent: run.intent, content: content, path: path, isOrdered: false, width: width)
        case .orderedList:
            return measureList(intent: run.intent, content: content, path: path, isOrdered: true, width: width)
        case .blockQuote:
            return measureQuote(intent: run.intent, content: content, path: path, width: width)
        case .thematicBreak:
            return AppKitMarkdownLayoutMeasurement(contentHeight: 1, naturalContentWidth: 0, fallbackRequired: false)
        case .table(let columns):
            return measureTable(intent: run.intent, content: content, columns: columns, width: width)
        default:
            return measureText(content, font: typography.body, weight: .regular, width: width)
        }
    }

    /// Mirrors `AppKitMarkdownDetailsBlockView`.
    ///
    /// Collapsed, a disclosure is its header and nothing else — no body height and no block
    /// spacing, because the view removes its body from the stack rather than hiding it at zero
    /// height. Adding a spacing here that the view does not draw is what would leave the pane
    /// reserving a gap under a collapsed section.
    private func measureDetails(
        _ block: AppMarkdownDetailsBlock,
        width: CGFloat,
        path: String
    ) -> AppKitMarkdownLayoutMeasurement {
        let summary = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: block.summary,
            baseFont: typography.body,
            inlineCodeFont: typography.inlineCode,
            weight: .regular,
            inlineCodeStyle: inlineCodeStyle,
            imageStore: imageStore
        )
        let chevronLane = AppMarkdownDetailsMetrics.chevronWidth + AppMarkdownDetailsMetrics.chevronSpacing
        let summarySize = measuredTextSize(summary, width: max(width - chevronLane, 0), wraps: true)
        let headerHeight = ceil(summarySize.height)
        let headerNaturalWidth = ceil(summarySize.width + chevronLane)

        let isExpanded = AppMarkdownDetailsExpansionStore.value(
            for: AppMarkdownDetailsExpansionStore.key(namespace: document.taskStateNamespace, path: path),
            defaultValue: block.isInitiallyOpen
        )
        guard isExpanded, !block.blocks.isEmpty else {
            return AppKitMarkdownLayoutMeasurement(
                contentHeight: headerHeight,
                naturalContentWidth: headerNaturalWidth,
                fallbackRequired: false
            )
        }

        let body = measureBlocks(
            block.blocks,
            width: max(width - AppMarkdownDetailsMetrics.bodyIndent, 0),
            path: path
        )
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(headerHeight + AppMarkdownDetailsMetrics.bodySpacing + body.contentHeight),
            naturalContentWidth: max(
                headerNaturalWidth,
                ceil(body.naturalContentWidth + AppMarkdownDetailsMetrics.bodyIndent)
            ),
            fallbackRequired: body.fallbackRequired
        )
    }

    private func measureText(
        _ content: AttributedString,
        font: NSFont,
        weight: NSFont.Weight,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let attributed = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: content,
            baseFont: font,
            inlineCodeFont: typography.inlineCode,
            weight: weight,
            inlineCodeStyle: inlineCodeStyle,
            imageStore: imageStore
        )
        return measureAttributedText(attributed, width: width)
    }

    private func measureCodeBlock(
        _ content: AttributedString,
        languageHint: String?,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let code = codeBlockText(content)
        if AppKitMarkdownCodeBlockView.rendersAsDiff(code: code, languageHint: languageHint) {
            return measureDiffCodeBlock(appKitCodeDisplayContent(code), width: width)
        }
        let attributed = AppKitMarkdownAttributedStringBuilder.syntaxHighlightedCode(
            appKitCodeDisplayContent(code),
            language: languageHint ?? "",
            colorScheme: colorScheme,
            font: typography.codeBlock
        )
        let textSize = measuredTextSize(attributed, width: .greatestFiniteMagnitude, wraps: false)
        let textNaturalWidth = ceil(textSize.width + codeBlockHorizontalInset * 2)
        let documentWidth = max(width, textNaturalWidth)
        let documentHeight = ceil(textSize.height + codeBlockVerticalInset * 2)
        let reserve = documentWidth > width + 0.5 ? appKitHorizontalOverflowScrollbarReserve : 0
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(documentHeight + reserve),
            naturalContentWidth: max(textNaturalWidth, codeBlockMinimumNaturalWidth),
            fallbackRequired: false
        )
    }

    /// Mirrors `AppKitDiffCodeBlockView`: only the code is laid out, and the gutter is a fixed
    /// leading offset the shared metrics resolve from the same rows.
    private func measureDiffCodeBlock(_ source: String, width: CGFloat) -> AppKitMarkdownLayoutMeasurement {
        let rows = DiffCodeHighlighting.rows(in: source)
        let metrics = AppKitDiffCodeBlockMetrics(rows: rows, font: typography.codeBlock)
        let attributed = AppKitDiffCodeBlockContent.attributedString(rows: rows, font: typography.codeBlock)
        let textSize = measuredTextSize(attributed, width: .greatestFiniteMagnitude, wraps: false)
        let naturalWidth = ceil(
            metrics.contentLeading + textSize.width + AppKitDiffCodeBlockMetrics.contentTrailingPadding
        )
        let documentWidth = max(width, naturalWidth)
        let documentHeight = ceil(textSize.height + AppKitDiffCodeBlockMetrics.verticalPadding * 2)
        let reserve = documentWidth > width + 0.5 ? appKitHorizontalOverflowScrollbarReserve : 0
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(documentHeight + reserve),
            naturalContentWidth: max(naturalWidth, codeBlockMinimumNaturalWidth),
            fallbackRequired: false
        )
    }

    private func measureList(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        path: String,
        isOrdered: Bool,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let itemRuns = content.appMarkdownBlockRuns(parent: intent)
        let rows = itemRuns.enumerated().map { index, itemRun in
            let itemContent = AttributedString(content[itemRun.range])
            let taskState = isOrdered ? nil : AppMarkdownTaskListState(content: itemContent)
            let markerWidth = markerWidth(isOrdered: isOrdered, taskState: taskState)
            let childWidth = max(width - markerWidth - 8, 0)
            let child = measureBlocks(
                taskState?.contentWithoutMarker ?? itemContent,
                parent: itemRun.intent,
                width: childWidth,
                path: path.appMarkdownAppendingPathComponent(index)
            )
            let markerHeight = markerHeight(taskState: taskState)
            return AppKitMarkdownLayoutMeasurement(
                contentHeight: max(markerHeight, child.contentHeight),
                naturalContentWidth: markerWidth + 8 + child.naturalContentWidth,
                fallbackRequired: child.fallbackRequired
            )
        }
        let spacing = AppKitMarkdownMetrics.listItemSpacing * CGFloat(max(rows.count - 1, 0))
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(rows.map(\.contentHeight).reduce(0, +) + spacing),
            naturalContentWidth: ceil(rows.map(\.naturalContentWidth).max() ?? 0),
            fallbackRequired: rows.contains(where: \.fallbackRequired)
        )
    }

    private func measureQuote(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        path: String,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let childWidth = max(width - AppKitMarkdownMetrics.quoteBarWidth - 10, 0)
        let child = measureBlocks(content, parent: intent, width: childWidth, path: path)
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: child.contentHeight,
            naturalContentWidth: AppKitMarkdownMetrics.quoteBarWidth + 10 + child.naturalContentWidth,
            fallbackRequired: child.fallbackRequired
        )
    }

    private func measureTable(
        intent: PresentationIntent.IntentType?,
        content: AttributedString,
        columns: [PresentationIntent.TableColumn],
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let rows = tableRows(intent: intent, content: content)
        let columnCount = max(columns.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else {
            return AppKitMarkdownLayoutMeasurement(contentHeight: 0, naturalContentWidth: 0, fallbackRequired: false)
        }
        let viewportWidth = tableViewportWidth(columnCount: columnCount, width: width)
        let tableWidth = max(CGFloat(columnCount) * tableMinimumColumnWidth, viewportWidth)
        let columnWidth = tableWidth / CGFloat(columnCount)
        let height = rows.enumerated().reduce(CGFloat.zero) { total, rowContext in
            let rowIndex = rowContext.offset
            let row = rowContext.element
            let rowHeight = (0..<columnCount).map { columnIndex in
                measureTableCell(
                    row[safe: columnIndex] ?? AttributedString(),
                    isHeader: rowIndex == 0,
                    width: columnWidth
                )
            }
            .max() ?? 0
            return total + rowHeight
        }
        let reserve = tableWidth > viewportWidth + 0.5 ? ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)) : 0
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(height + reserve),
            naturalContentWidth: viewportWidth,
            fallbackRequired: false
        )
    }

    private func measureTableCell(
        _ content: AttributedString,
        isHeader: Bool,
        width: CGFloat
    ) -> CGFloat {
        let attributed = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: content,
            baseFont: typography.body,
            inlineCodeFont: typography.inlineCode,
            weight: isHeader ? .semibold : .regular,
            inlineCodeStyle: inlineCodeStyle,
            imageStore: imageStore
        )
        let textWidth = max(width - tableCellHorizontalPadding * 2, 0)
        return ceil(measuredTextSize(attributed, width: textWidth, wraps: true).height + tableCellVerticalPadding * 2)
    }

    private func measureAttributedText(
        _ attributed: NSAttributedString,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let textSize = measuredTextSize(attributed, width: width, wraps: true)
        let naturalRect = attributed.boundingRect(
            with: NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude / 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: ceil(textSize.height),
            naturalContentWidth: ceil(naturalRect.width),
            fallbackRequired: false
        )
    }

    private func measuredTextSize(
        _ attributed: NSAttributedString,
        width: CGFloat,
        wraps: Bool
    ) -> NSSize {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let containerWidth = wraps ? max(width, 0) : CGFloat.greatestFiniteMagnitude
        let textContainer = NSTextContainer(size: NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = wraps
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: ceil(usedRect.width), height: ceil(usedRect.height))
    }

    private func markerWidth(isOrdered: Bool, taskState: AppMarkdownTaskListState?) -> CGFloat {
        if taskState != nil {
            return AppKitMarkdownMetrics.taskMarkerWidth
        }
        return isOrdered ? AppKitMarkdownMetrics.orderedListMarkerWidth : AppKitMarkdownMetrics.unorderedListMarkerWidth
    }

    private func markerHeight(taskState: AppMarkdownTaskListState?) -> CGFloat {
        if taskState != nil {
            return 16
        }
        return ceil(typography.body.ascender - typography.body.descender + typography.body.leading)
    }

    private func tableViewportWidth(columnCount: Int, width: CGFloat) -> CGFloat {
        let naturalWidth = CGFloat(columnCount) * tableMinimumColumnWidth
        if width > 0 {
            return min(naturalWidth, width)
        }
        return min(naturalWidth, tableFallbackViewportWidth)
    }

    private func tableRows(
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

    private func isDelimiterRow(_ cells: [AttributedString]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            let text = String(cell.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private func codeBlockText(_ content: AttributedString) -> String {
        let value = String(content.characters)
        return value.hasSuffix("\n") ? String(value.dropLast()) : value
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
