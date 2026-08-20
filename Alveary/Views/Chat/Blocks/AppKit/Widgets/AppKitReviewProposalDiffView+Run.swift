import AppKit

/// A run of consecutive diff lines between two comment cards, drawn with the same gutter a fenced
/// diff block gets.
///
/// One view draws the whole run — gutter washes, line numbers, and file-header chrome in
/// `draw(_:)`, one frame-positioned label per line for the code text — because the card's cost is
/// dominated by Auto Layout solving its subview tree: at one constraint-participating `NSView` per
/// diff line, a five-file preview mounted ~75 of them and each of the transcript's two measurement
/// passes re-solved them all (~150ms per configure, measured 19-08-2026). Runs cut the stack to
/// one arranged view per segment, and their labels stay out of the constraint graph entirely.
///
/// The labels stay real `NSTextField`s rather than drawn strings so per-line truncation, font
/// fallback, and VoiceOver's per-line static text all keep AppKit's behavior.
@MainActor
final class AppKitReviewProposalDiffRunView: NSView {
    /// Tighter than a fenced block's 10pt so the card stays a summary; the fence is a reading
    /// surface, this is a confirmation.
    static let verticalPadding: CGFloat = 1
    /// A file header is the only thing separating one file's lines from the next, and at the code
    /// rows' 1pt rhythm it read as just another line. The extra room, the banded fill, and the
    /// rules framing it are what make it land as a section break.
    static let fileHeaderVerticalPadding: CGFloat = 6

    private var rows: [DiffCodeHighlighting.Row] = []
    private var metrics = AppKitDiffCodeBlockMetrics.empty
    private var codeFont: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    /// Each row's slice within the run — full width, at the stacked y its label was placed
    /// against. Heights come from the labels' intrinsic sizes, so text and wash cannot drift.
    private var rowSlices: [NSRect] = []
    private var fieldPool: [NSTextField] = []
    /// Measured once per `configure`, because the card asks every run for this while measuring
    /// itself and `attributedStringValue.size()` is real text layout.
    private(set) var naturalWidth: CGFloat = 0
    private var totalHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: totalHeight)
    }

    func configure(rows: [DiffCodeHighlighting.Row], metrics: AppKitDiffCodeBlockMetrics, font: NSFont) {
        self.rows = rows
        self.metrics = metrics
        codeFont = font
        rowSlices.removeAll(keepingCapacity: true)
        naturalWidth = 0
        var currentY: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let field = field(at: index)
            configureField(field, for: row, font: font)
            let padding = Self.padding(for: row)
            let fieldHeight = field.intrinsicContentSize.height
            rowSlices.append(NSRect(x: 0, y: currentY, width: 0, height: fieldHeight + padding * 2))
            field.frame.origin.y = currentY + padding
            field.frame.size.height = fieldHeight
            naturalWidth = max(
                naturalWidth,
                ceil(
                    metrics.contentLeading
                        + field.attributedStringValue.size().width
                        + AppKitDiffCodeBlockMetrics.contentTrailingPadding
                )
            )
            currentY += fieldHeight + padding * 2
        }
        totalHeight = currentY
        for extra in fieldPool[rows.count...] {
            extra.removeFromSuperview()
        }
        fieldPool.removeSubrange(rows.count...)
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    /// The labels' widths track the run's, and the washes fill it, so a resize redraws everything.
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - metrics.contentLeading - AppKitDiffCodeBlockMetrics.contentTrailingPadding)
        for field in fieldPool {
            field.frame.origin.x = metrics.contentLeading
            field.frame.size.width = width
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, slice) in rowSlices.enumerated() where index < rows.count {
            let frame = NSRect(x: 0, y: slice.origin.y, width: bounds.width, height: slice.height)
            guard frame.intersects(dirtyRect) else {
                continue
            }
            let row = rows[index]
            AppKitDiffGutterPainter.draw(row: row, in: frame, metrics: metrics, font: codeFont)
            if row.kind == .fileHeader {
                drawFileHeaderChrome(in: frame)
            }
            AppKitDiffGutterPainter.drawSeparator(in: frame, metrics: metrics)
        }
    }
}

private extension AppKitReviewProposalDiffRunView {
    static func padding(for row: DiffCodeHighlighting.Row) -> CGFloat {
        row.kind == .fileHeader ? fileHeaderVerticalPadding : verticalPadding
    }

    func field(at index: Int) -> NSTextField {
        if index < fieldPool.count {
            return fieldPool[index]
        }
        let field = NSTextField(labelWithString: "")
        // The card cannot scroll, so an overlong line truncates rather than widening the bubble;
        // `configureField` picks which end truncates.
        field.maximumNumberOfLines = 1
        field.autoresizingMask = []
        addSubview(field)
        fieldPool.append(field)
        return field
    }

    func configureField(_ field: NSTextField, for row: DiffCodeHighlighting.Row, font: NSFont) {
        let isFileHeader = row.kind == .fileHeader
        // A file header is the card's only navigation aid, so it stays semibold — and a point
        // larger than the code — where a fenced block renders every non-gutter row in the same
        // monospaced face.
        field.font = isFileHeader
            ? .systemFont(ofSize: font.pointSize + 1, weight: .semibold)
            : font
        // A path disambiguates on its tail, so a long one keeps its trailing components.
        field.lineBreakMode = isFileHeader ? .byTruncatingHead : .byTruncatingTail
        field.textColor = isFileHeader || row.occupiesGutter ? .labelColor : .secondaryLabelColor
        field.stringValue = row.text
    }

    /// A band across the full row, framed by a rule top and bottom. Painted over the painter's
    /// gutter wash on purpose — an unbroken band is what separates one file from the previous
    /// file's last line. It lives here rather than in `AppKitDiffGutterPainter` so a fenced diff's
    /// own `diff --git` header keeps the look it already had.
    ///
    /// The tints are deliberately heavier than `AppKitDiffCodeBlockPalette`'s hunk-header wash: at
    /// that weight, beside added and deleted rows carrying their own colour, the path still read as
    /// one more line of content rather than as the start of a file.
    func drawFileHeaderChrome(in frame: NSRect) {
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.1).setFill()
        frame.fill()
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.15).setFill()
        NSRect(x: 0, y: frame.origin.y, width: frame.width, height: 1).fill()
        NSRect(x: 0, y: frame.maxY - 1, width: frame.width, height: 1).fill()
    }
}
