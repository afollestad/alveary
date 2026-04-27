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
        let renderedColumnWidths = columnWidths(for: renderedRows)

        ViewThatFits(in: .horizontal) {
            tableContent(rows: renderedRows, columnWidths: renderedColumnWidths)

            ScrollView(.horizontal) {
                tableContent(rows: renderedRows, columnWidths: renderedColumnWidths)
            }
        }
    }

    private func tableContent(
        rows: [AppMarkdownTableRow],
        columnWidths: [CGFloat]
    ) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow(alignment: .top) {
                    ForEach(rows[rowIndex].cells.indices, id: \.self) { columnIndex in
                        AppMarkdownTableCell(
                            content: rows[rowIndex].cells[columnIndex],
                            isHeader: rowIndex == 0,
                            inlineCodeStyle: inlineCodeStyle,
                            width: columnWidths[safe: columnIndex] ?? 72,
                            alignment: alignment(for: columnIndex)
                        )
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
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

    private func columnWidths(for rows: [AppMarkdownTableRow]) -> [CGFloat] {
        let columnCount = max(columns.count, rows.map(\.cells.count).max() ?? 0)
        return (0..<columnCount).map { columnIndex in
            let widestCharacterCount = rows
                .compactMap { row in row.cells[safe: columnIndex] }
                .map { String($0.characters).count }
                .max() ?? 0
            return max(72, CGFloat(widestCharacterCount) * 9 + 22)
        }
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

private struct AppMarkdownTableCell: View {
    let content: AttributedString
    let isHeader: Bool
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let width: CGFloat
    let alignment: Alignment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppMarkdownInlineText(content: content, inlineCodeStyle: inlineCodeStyle)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: width, alignment: alignment)
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
