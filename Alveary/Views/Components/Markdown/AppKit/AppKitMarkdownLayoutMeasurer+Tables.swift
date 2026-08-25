@preconcurrency import AppKit
import Foundation

/// Table measurement for `AppKitMarkdownLayoutMeasurer`, split out to keep the measurer itself
/// readable. Everything here mirrors `AppKitMarkdownTableView`: the same equal-width columns, the
/// same image-cell floor, and the same reserved lane under a table wide enough to scroll.
extension AppKitMarkdownLayoutMeasurer {
    func measureTable(
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
        let columnWidthFloor = columnWidthFloor(rows: rows)
        let viewportWidth = tableViewportWidth(columnCount: columnCount, columnWidthFloor: columnWidthFloor, width: width)
        let tableWidth = max(CGFloat(columnCount) * columnWidthFloor, viewportWidth)
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
        if let cellImage = content.appMarkdownSoleInlineImage {
            let imageHeight = AppKitMarkdownTableMetrics
                .imageDisplaySize(for: cellImage, store: imageStore, inCellWidth: width)
                .height
            return ceil(imageHeight + AppKitMarkdownTableMetrics.cellVerticalPadding * 2)
        }
        let attributed = AppKitMarkdownAttributedStringBuilder.attributedString(
            from: content,
            baseFont: typography.body,
            inlineCodeFont: typography.inlineCode,
            weight: isHeader ? .semibold : .regular,
            inlineCodeStyle: inlineCodeStyle,
            imageStore: imageStore
        )
        let textWidth = max(width - AppKitMarkdownTableMetrics.cellHorizontalPadding * 2, 0)
        let textHeight = appKitMarkdownMeasuredTextSize(attributed, width: textWidth, wraps: true).height
        return ceil(textHeight + AppKitMarkdownTableMetrics.cellVerticalPadding * 2)
    }

    private func tableViewportWidth(columnCount: Int, columnWidthFloor: CGFloat, width: CGFloat) -> CGFloat {
        let naturalWidth = CGFloat(columnCount) * columnWidthFloor
        if width > 0 {
            return min(naturalWidth, width)
        }
        return min(naturalWidth, AppKitMarkdownTableMetrics.fallbackViewportWidth)
    }

    /// Mirrors `AppKitMarkdownTableView`'s floor: the widest image cell raises every equal-width
    /// column, so a fitted bitmap is not squeezed into the text-table minimum.
    private func columnWidthFloor(rows: [[AttributedString]]) -> CGFloat {
        rows.lazy.joined().reduce(AppKitMarkdownTableMetrics.minimumColumnWidth) { floor, cell in
            guard let cellImage = cell.appMarkdownSoleInlineImage else {
                return floor
            }
            let width = AppKitMarkdownTableMetrics.imageDisplaySize(for: cellImage, store: imageStore).width
            return max(floor, width + AppKitMarkdownTableMetrics.cellHorizontalPadding * 2)
        }
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
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
