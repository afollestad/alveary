import AppKit

/// One diff line of a review proposal's preview, drawn with the same gutter a fenced diff gets.
///
/// The card stacks one of these per line so comment cards can sit between them, which is why the
/// row draws its own hairline segment rather than sharing one spanning view: stacked segments read
/// as the single continuous line `AppKitDiffCodeBlockView` draws in one pass.
@MainActor
final class AppKitReviewProposalDiffRowView: NSView {
    /// Tighter than a fenced block's 10pt so the card stays a summary; the fence is a reading
    /// surface, this is a confirmation.
    static let verticalPadding: CGFloat = 1
    /// A file header is the only thing separating one file's lines from the next, and at the code
    /// rows' 1pt rhythm it read as just another line. The extra room, the banded fill, and the
    /// rules framing it are what make it land as a section break.
    static let fileHeaderVerticalPadding: CGFloat = 6

    private let textField = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var row: DiffCodeHighlighting.Row?
    private var metrics = AppKitDiffCodeBlockMetrics.empty
    private var codeFont: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    /// Measured once per `configure` rather than per query: the card asks every row for this
    /// while measuring itself, and `attributedStringValue.size()` is real text layout.
    private(set) var naturalWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        // The card cannot scroll, so an overlong line truncates rather than widening the bubble;
        // configure(row:metrics:font:) picks which end truncates.
        textField.maximumNumberOfLines = 1
        addSubview(textField)
        let leading = textField.leadingAnchor.constraint(equalTo: leadingAnchor)
        let top = textField.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding)
        let bottom = textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding)
        leadingConstraint = leading
        topConstraint = top
        bottomConstraint = bottom
        NSLayoutConstraint.activate([
            leading,
            textField.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -AppKitDiffCodeBlockMetrics.contentTrailingPadding
            ),
            top,
            bottom
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func configure(row: DiffCodeHighlighting.Row, metrics: AppKitDiffCodeBlockMetrics, font: NSFont) {
        self.row = row
        self.metrics = metrics
        codeFont = font
        let isFileHeader = row.kind == .fileHeader
        // A file header is the card's only navigation aid, so it stays semibold — and a point
        // larger than the code — where a fenced block renders every non-gutter row in the same
        // monospaced face.
        textField.font = isFileHeader
            ? .systemFont(ofSize: font.pointSize + 1, weight: .semibold)
            : font
        // A path disambiguates on its tail, so a long one keeps its trailing components.
        textField.lineBreakMode = isFileHeader ? .byTruncatingHead : .byTruncatingTail
        textField.textColor = isFileHeader || row.occupiesGutter ? .labelColor : .secondaryLabelColor
        textField.stringValue = row.text
        leadingConstraint?.constant = metrics.contentLeading
        let padding = isFileHeader ? Self.fileHeaderVerticalPadding : Self.verticalPadding
        topConstraint?.constant = padding
        bottomConstraint?.constant = -padding
        naturalWidth = ceil(
            metrics.contentLeading
                + textField.attributedStringValue.size().width
                + AppKitDiffCodeBlockMetrics.contentTrailingPadding
        )
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let row else {
            return
        }
        AppKitDiffGutterPainter.draw(row: row, in: bounds, metrics: metrics, font: codeFont)
        if row.kind == .fileHeader {
            drawFileHeaderChrome()
        }
        AppKitDiffGutterPainter.drawSeparator(in: bounds, metrics: metrics)
    }
}

private extension AppKitReviewProposalDiffRowView {
    /// A band across the full row, framed by a rule top and bottom. Painted over the painter's
    /// gutter wash on purpose — an unbroken band is what separates one file from the previous
    /// file's last line. It lives here rather than in `AppKitDiffGutterPainter` so a fenced diff's
    /// own `diff --git` header keeps the look it already had.
    ///
    /// The tints are deliberately heavier than `AppKitDiffCodeBlockPalette`'s hunk-header wash: at
    /// that weight, beside added and deleted rows carrying their own colour, the path still read as
    /// one more line of content rather than as the start of a file.
    func drawFileHeaderChrome() {
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.1).setFill()
        bounds.fill()
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.15).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
