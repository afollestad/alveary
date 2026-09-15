import AppKit

/// A rejected candidate keeps its location, comment, and evidence separate. Long comments and
/// vote rationales disclose independently so inspecting one finding does not unfold every report.
@MainActor
final class AppKitReviewTeamNotProposedFindingView: NSView {
    let findingID: String
    var onHeightInvalidated: (() -> Void)?

    private let stack = NSStackView()
    private let location = NSTextField(labelWithString: "")
    private let bodyField = NSTextField(labelWithString: "")
    private let bodyToggle = AppKitTranscriptHeaderToggleButton()
    private let evidence = AppKitReviewProposalVoteEvidenceView()
    private var toggleHeight: NSLayoutConstraint?
    private var bodyHeight: NSLayoutConstraint?
    private var isBodyExpanded = false
    private var layoutWidth: CGFloat = 0
    private var previewHeight: CGFloat = 0
    private var bodySource: String?

    init(findingID: String) {
        self.findingID = findingID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    /// A paragraph's unconstrained width would stretch the whole card to the transcript cap.
    var naturalWidth: CGFloat { ceil(location.cell?.cellSize.width ?? 0) }

    func configure(
        finding: ReviewCanonicalFinding,
        votes: [ReviewTeamVote],
        reviewers: [PullRequestReviewProposalRecord.Reviewer],
        typography: TranscriptTypography
    ) {
        if bodySource != finding.body { isBodyExpanded = false }
        bodySource = finding.body
        location.stringValue = "\((finding.path as NSString).lastPathComponent):\(finding.line)"
        location.font = typography.nsFont(.caption, weight: .medium)
        location.textColor = .secondaryLabelColor
        location.toolTip = "\(finding.path):\(finding.line)"
        location.setAccessibilityLabel("\(finding.path), line \(finding.line)")
        let font = typography.nsFont(.caption)
        let body = NSMutableAttributedString(attributedString: AppKitMarkdownInlineString.attributedString(
            for: finding.body, baseFont: font, foregroundColor: .labelColor
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        body.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: body.length))
        bodyField.attributedStringValue = body
        bodyField.setAccessibilityLabel(body.string)
        previewHeight = ceil(NSLayoutManager().defaultLineHeight(for: font)) * 4
        bodyToggle.font = typography.nsFont(.caption, weight: .medium)
        toggleHeight?.constant = max(24, ceil(NSLayoutManager().defaultLineHeight(for: font)) + 6)
        evidence.configure(
            findingID: finding.id, votes: votes, reviewers: reviewers, typography: typography,
            initiallyExpanded: false, compact: true
        )
        prepareLayout(width: layoutWidth)
    }

    func prepareLayout(width: CGFloat) {
        layoutWidth = width
        guard width > 0 else { return }
        let height = ceil(bodyField.cell?.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: width, height: .greatestFiniteMagnitude
        )).height ?? 0)
        let overflows = height > previewHeight
        bodyHeight?.constant = isBodyExpanded ? height : min(height, previewHeight)
        bodyToggle.isHidden = !overflows
        bodyToggle.title = isBodyExpanded ? "Show less" : "Show more"
        bodyToggle.symbolName = isBodyExpanded ? "chevron.up" : "chevron.down"
        bodyToggle.setAccessibilityLabel(isBodyExpanded ? "Show less of this finding" : "Show the full finding")
    }

    private func setup() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        location.translatesAutoresizingMaskIntoConstraints = false
        location.lineBreakMode = .byTruncatingMiddle
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addFullWidthArrangedSubview(location)
        bodyField.translatesAutoresizingMaskIntoConstraints = false
        bodyField.maximumNumberOfLines = 0
        bodyField.lineBreakMode = .byWordWrapping
        bodyField.isSelectable = true
        bodyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bodyHeight = bodyField.heightAnchor.constraint(equalToConstant: 0)
        bodyHeight?.isActive = true
        stack.addFullWidthArrangedSubview(bodyField)
        bodyToggle.translatesAutoresizingMaskIntoConstraints = false
        toggleHeight = bodyToggle.heightAnchor.constraint(equalToConstant: 24)
        toggleHeight?.isActive = true
        bodyToggle.isBordered = false
        bodyToggle.identifier = NSUserInterfaceItemIdentifier("finding-body:\(findingID)")
        bodyToggle.target = self
        bodyToggle.action = #selector(toggleBody)
        stack.addArrangedSubview(bodyToggle)
        evidence.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        stack.addFullWidthArrangedSubview(evidence)
    }

    @objc
    private func toggleBody() {
        isBodyExpanded.toggle()
        prepareLayout(width: layoutWidth)
        onHeightInvalidated?()
    }
}
