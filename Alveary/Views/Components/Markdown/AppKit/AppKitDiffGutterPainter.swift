@preconcurrency import AppKit

/// Draws one diff row's wash, gutter columns, and the hairline dividing them from the code.
///
/// Two surfaces draw diff gutters: `AppKitDiffCodeBlockView` paints every row of a fenced diff into
/// one view, and the review-proposal card paints one row per stacked view so comment cards can sit
/// between them. Both go through here so the columns, washes, and hairline cannot drift apart.
///
/// Every rect here is measured from the gutter's own left edge, matching
/// `AppKitDiffCodeBlockMetrics`' column rects: callers pass full-width frames starting at `x = 0`
/// and vary only `y` and `height`.
@MainActor
enum AppKitDiffGutterPainter {
    /// Fills `frame` with the row's wash and gutter tint, then draws its number and marker columns.
    static func draw(
        row: DiffCodeHighlighting.Row,
        in frame: NSRect,
        metrics: AppKitDiffCodeBlockMetrics,
        font: NSFont
    ) {
        if let wash = AppKitDiffCodeBlockPalette.rowWash(for: row.kind) {
            wash.setFill()
            frame.fill()
        }
        AppKitDiffCodeBlockPalette.gutterWash(for: row.kind).setFill()
        gutterRect(in: frame, metrics: metrics).fill()
        guard row.occupiesGutter else {
            return
        }
        drawGutterText(row, in: frame, metrics: metrics, font: font)
    }

    /// The gutter's own column, for callers that tint it without a row — a comment card's wash bands.
    static func gutterRect(in frame: NSRect, metrics: AppKitDiffCodeBlockMetrics) -> NSRect {
        NSRect(x: 0, y: frame.origin.y, width: metrics.gutterWidth, height: frame.height)
    }

    /// The hairline between the gutter and the code, spanning `rect` vertically. Stacked callers
    /// draw one segment per row, which reads as the single continuous line a one-view caller draws.
    static func drawSeparator(in rect: NSRect, metrics: AppKitDiffCodeBlockMetrics) {
        AppKitDiffCodeBlockPalette.separator.setFill()
        NSRect(
            x: metrics.gutterWidth - AppKitDiffCodeBlockMetrics.separatorWidth,
            y: rect.origin.y,
            width: AppKitDiffCodeBlockMetrics.separatorWidth,
            height: rect.height
        ).fill()
    }

    private static func drawGutterText(
        _ row: DiffCodeHighlighting.Row,
        in frame: NSRect,
        metrics: AppKitDiffCodeBlockMetrics,
        font: NSFont
    ) {
        if metrics.showsLineNumbers {
            drawColumnText(
                row.oldNumber.map(String.init),
                in: metrics.oldNumberColumn(in: frame),
                color: .secondaryLabelColor,
                font: font
            )
            drawColumnText(
                row.newNumber.map(String.init),
                in: metrics.newNumberColumn(in: frame),
                color: .secondaryLabelColor,
                font: font
            )
        }
        drawColumnText(
            row.marker,
            in: metrics.markerColumn(in: frame),
            color: AppKitDiffCodeBlockPalette.markerColor(for: row.kind),
            font: font
        )
    }

    /// Right-aligned inside its column, and vertically centered on the row rather than sharing the
    /// text view's baseline, so a column keeps reading straight even at a different glyph height.
    private static func drawColumnText(_ text: String?, in column: NSRect, color: NSColor, font: NSFont) {
        guard let text, !text.isEmpty else {
            return
        }
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = attributed.size()
        attributed.draw(
            at: NSPoint(
                x: column.maxX - ceil(size.width),
                y: column.origin.y + (column.height - size.height) / 2
            )
        )
    }
}
