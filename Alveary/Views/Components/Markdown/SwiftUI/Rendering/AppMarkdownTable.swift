import Foundation
import SwiftUI

struct AppMarkdownTable: View {
    let intent: PresentationIntent.IntentType?
    let content: AttributedSubstring
    let columns: [PresentationIntent.TableColumn]
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let renderedRows = rows
        let renderedColumnCount = columnCount(for: renderedRows)

        ViewThatFits(in: .horizontal) {
            tableContent(rows: renderedRows, columnCount: renderedColumnCount)

            ScrollView(.horizontal) {
                tableContent(rows: renderedRows, columnCount: renderedColumnCount)
            }
        }
    }

    private func tableContent(
        rows: [AppMarkdownTableRow],
        columnCount: Int
    ) -> some View {
        AppMarkdownTableGridLayout(columnCount: columnCount) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    if let cell = rows[rowIndex].cells[safe: columnIndex] {
                        AppMarkdownTableCell(
                            content: cell,
                            isHeader: rowIndex == 0,
                            inlineCodeStyle: inlineCodeStyle,
                            alignment: alignment(for: columnIndex)
                        )
                    } else {
                        AppMarkdownTableCell(
                            content: AttributedString(),
                            isHeader: rowIndex == 0,
                            inlineCodeStyle: inlineCodeStyle,
                            alignment: alignment(for: columnIndex)
                        )
                    }
                }
            }
        }
        .background(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: markdownTableCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: markdownTableCornerRadius, style: .continuous)
                .stroke(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme), lineWidth: 1)
        )
    }

    private var rows: [AppMarkdownTableRow] {
        content.appMarkdownBlockRuns(parent: intent).map { rowRun in
            let rowContent = content[rowRun.range]
            let cellRuns = rowContent.appMarkdownBlockRuns(parent: rowRun.intent)
            return AppMarkdownTableRow(
                cells: cellRuns.map { cellRun in
                    AttributedString(rowContent[cellRun.range])
                }
            )
        }
    }

    private func columnCount(for rows: [AppMarkdownTableRow]) -> Int {
        max(columns.count, rows.map(\.cells.count).max() ?? 0)
    }

    private func alignment(for columnIndex: Int) -> Alignment {
        guard columnIndex < columns.count else {
            return .leading
        }
        switch columns[columnIndex].alignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        @unknown default:
            return .leading
        }
    }
}

private struct AppMarkdownTableRow {
    let cells: [AttributedString]
}

private struct AppMarkdownTableGridLayout<Content: View>: View {
    let columnCount: Int
    let content: Content

    init(columnCount: Int, @ViewBuilder content: () -> Content) {
        self.columnCount = columnCount
        self.content = content()
    }

    var body: some View {
        AppMarkdownTableMeasuredGridLayout(columnCount: columnCount) {
            content
        }
    }
}

private struct AppMarkdownTableMeasuredGridLayout: Layout {
    let columnCount: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let columnWidths = measuredColumnWidths(subviews: subviews)
        let rowHeights = measuredRowHeights(subviews: subviews, columnWidths: columnWidths)
        return CGSize(
            width: columnWidths.reduce(0, +),
            height: rowHeights.reduce(0, +)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnWidths = measuredColumnWidths(subviews: subviews)
        let rowHeights = measuredRowHeights(subviews: subviews, columnWidths: columnWidths)
        var currentY = bounds.minY

        for rowIndex in rowHeights.indices {
            var currentX = bounds.minX
            for columnIndex in columnWidths.indices {
                let subviewIndex = rowIndex * columnCount + columnIndex
                guard subviewIndex < subviews.count else {
                    continue
                }
                subviews[subviewIndex].place(
                    at: CGPoint(x: currentX, y: currentY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: columnWidths[columnIndex],
                        height: rowHeights[rowIndex]
                    )
                )
                currentX += columnWidths[columnIndex]
            }
            currentY += rowHeights[rowIndex]
        }
    }

    private func measuredColumnWidths(subviews: Subviews) -> [CGFloat] {
        guard columnCount > 0 else {
            return []
        }

        return (0..<columnCount).map { columnIndex in
            subviews.indices
                .filter { $0 % columnCount == columnIndex }
                .map { subviews[$0].sizeThatFits(.unspecified).width }
                .max() ?? 0
        }
    }

    private func measuredRowHeights(
        subviews: Subviews,
        columnWidths: [CGFloat]
    ) -> [CGFloat] {
        guard columnCount > 0 else {
            return []
        }

        let rowCount = Int(ceil(Double(subviews.count) / Double(columnCount)))
        return (0..<rowCount).map { rowIndex in
            columnWidths.indices.compactMap { columnIndex in
                let subviewIndex = rowIndex * columnCount + columnIndex
                guard subviewIndex < subviews.count else {
                    return nil
                }
                return subviews[subviewIndex]
                    .sizeThatFits(ProposedViewSize(width: columnWidths[columnIndex], height: nil))
                    .height
            }
            .max() ?? 0
        }
    }
}

private struct AppMarkdownTableCell: View {
    let content: AttributedString
    let isHeader: Bool
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let alignment: Alignment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppMarkdownInlineText(content: content, inlineCodeStyle: inlineCodeStyle)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme))
                    .frame(height: 1)
            }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
