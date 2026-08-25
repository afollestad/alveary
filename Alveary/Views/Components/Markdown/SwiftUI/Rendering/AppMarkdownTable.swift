import Foundation
import SwiftUI

struct AppMarkdownTable: View {
    let intent: PresentationIntent.IntentType?
    let content: AttributedSubstring
    let columns: [PresentationIntent.TableColumn]
    let inlineCodeStyle: AppMarkdownInlineCodeStyle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appMarkdownImageStore) private var environmentStore

    var body: some View {
        let store = environmentStore ?? .shared
        let renderedRows = rows
        let renderedColumnCount = columnCount(for: renderedRows)
        // Image cells resize the moment their bitmap resolves, and the grid layout caches column
        // widths across passes, so its cache has to know a load happened. Text cells count too:
        // an image sharing a line with text swaps alt text for a bitmap and moves its row's height.
        let fingerprint = store.loadStateFingerprint(
            forImages: renderedRows.flatMap(\.cells).flatMap(\.appMarkdownInlineImages)
        )

        ViewThatFits(in: .horizontal) {
            tableContent(
                rows: renderedRows,
                columnCount: renderedColumnCount,
                store: store,
                imageLoadFingerprint: fingerprint
            )

            ScrollView(.horizontal) {
                tableContent(
                    rows: renderedRows,
                    columnCount: renderedColumnCount,
                    store: store,
                    imageLoadFingerprint: fingerprint
                )
            }
        }
    }

    private func tableContent(
        rows: [AppMarkdownTableRow],
        columnCount: Int,
        store: AppMarkdownImageStore,
        imageLoadFingerprint: String
    ) -> some View {
        AppMarkdownTableGridLayout(columnCount: columnCount, imageLoadFingerprint: imageLoadFingerprint) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    AppMarkdownTableCell(
                        content: cellContent(for: rows[rowIndex].cells[safe: columnIndex], store: store),
                        isHeader: rowIndex == 0,
                        inlineCodeStyle: inlineCodeStyle,
                        alignment: alignment(for: columnIndex)
                    )
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

    /// Resolves an image cell's box here rather than inside the cell view, because this is where the
    /// store's load state is observed. A cell view deciding it from its own stored properties never
    /// re-evaluates when a bitmap arrives — those properties are identical across the load — so the
    /// loaded image kept drawing inside the placeholder's 16:9 box.
    private func cellContent(
        for cell: AttributedString?,
        store: AppMarkdownImageStore
    ) -> AppMarkdownTableCellContent {
        guard let cell else {
            return .text(AttributedString())
        }
        guard let cellImage = cell.appMarkdownSoleInlineImage else {
            return .text(cell)
        }
        let displaySize = appMarkdownImageDisplaySize(
            for: cellImage.image.appMarkdownResolved(
                naturalSize: store.naturalSize(for: cellImage.image, baseURL: nil)
            ),
            constrainedTo: appMarkdownTableImageCellMaxSize
        )
        return .image(cellImage, displaySize: displaySize)
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
    let imageLoadFingerprint: String
    let content: Content

    init(columnCount: Int, imageLoadFingerprint: String, @ViewBuilder content: () -> Content) {
        self.columnCount = columnCount
        self.imageLoadFingerprint = imageLoadFingerprint
        self.content = content()
    }

    var body: some View {
        AppMarkdownTableMeasuredGridLayout(columnCount: columnCount, imageLoadFingerprint: imageLoadFingerprint) {
            content
        }
    }
}

private struct AppMarkdownTableMeasuredGridLayout: Layout {
    let columnCount: Int
    /// Part of the cached measurement's identity, not just of `updateCache`'s trigger: an image
    /// cell measures one size as a placeholder and another once its bitmap resolves, and the cache
    /// otherwise keeps serving the pre-load column widths.
    let imageLoadFingerprint: String

    func makeCache(subviews: Subviews) -> AppMarkdownTableGridLayoutCache {
        AppMarkdownTableGridLayoutCache()
    }

    func updateCache(
        _ cache: inout AppMarkdownTableGridLayoutCache,
        subviews: Subviews
    ) {
        cache = AppMarkdownTableGridLayoutCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout AppMarkdownTableGridLayoutCache
    ) -> CGSize {
        measurement(subviews: subviews, cache: &cache).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout AppMarkdownTableGridLayoutCache
    ) {
        let measurement = measurement(subviews: subviews, cache: &cache)
        let columnWidths = measurement.columnWidths
        let rowHeights = measurement.rowHeights
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

    private func measurement(
        subviews: Subviews,
        cache: inout AppMarkdownTableGridLayoutCache
    ) -> AppMarkdownTableGridLayoutMeasurement {
        if let measurement = cache.measurement,
           measurement.columnCount == columnCount,
           measurement.subviewCount == subviews.count,
           measurement.imageLoadFingerprint == imageLoadFingerprint {
            return measurement
        }

        let columnWidths = measuredColumnWidths(subviews: subviews)
        let rowHeights = measuredRowHeights(subviews: subviews, columnWidths: columnWidths)
        let measurement = AppMarkdownTableGridLayoutMeasurement(
            columnCount: columnCount,
            subviewCount: subviews.count,
            imageLoadFingerprint: imageLoadFingerprint,
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            size: CGSize(
                width: columnWidths.reduce(0, +),
                height: rowHeights.reduce(0, +)
            )
        )
        cache.measurement = measurement
        return measurement
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

private struct AppMarkdownTableGridLayoutCache {
    var measurement: AppMarkdownTableGridLayoutMeasurement?
}

private struct AppMarkdownTableGridLayoutMeasurement {
    let columnCount: Int
    let subviewCount: Int
    let imageLoadFingerprint: String
    let columnWidths: [CGFloat]
    let rowHeights: [CGFloat]
    let size: CGSize
}

/// What one cell draws, decided in `AppMarkdownTable.body` where the image store is observed.
///
/// An image cell carries a *fixed* box rather than a maximum, because
/// `AppMarkdownTableMeasuredGridLayout` sizes each column from `sizeThatFits(.unspecified)`: a fixed
/// box makes the image the widest cell in its column and therefore *is* the column width. Rendering
/// the image inline instead would size it at its natural width — 720pt for a phone capture — and
/// push the whole table into the horizontal-overflow variant. A pane too narrow for even the fitted
/// cells still falls to that variant, the same way any over-wide table does; the cells do not shrink
/// below the cap.
private enum AppMarkdownTableCellContent {
    case image(AppMarkdownCellImage, displaySize: CGSize)
    case text(AttributedString)
}

private struct AppMarkdownTableCell: View {
    let content: AppMarkdownTableCellContent
    let isHeader: Bool
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    let alignment: Alignment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        cellContent
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

    @ViewBuilder
    private var cellContent: some View {
        switch content {
        case let .image(cellImage, displaySize):
            AppMarkdownImageBlockView(
                block: AppMarkdownImageBlock(image: cellImage.image),
                linkURL: cellImage.link,
                maxDisplaySize: displaySize
            )
            .frame(width: displaySize.width, height: displaySize.height)
        case let .text(text):
            AppMarkdownInlineText(content: text, inlineCodeStyle: inlineCodeStyle)
                .fontWeight(isHeader ? .semibold : .regular)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
