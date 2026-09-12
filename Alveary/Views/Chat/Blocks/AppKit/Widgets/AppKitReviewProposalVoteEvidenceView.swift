import AppKit

/// The reviewer decisions supporting one collectively proposed comment.
@MainActor
final class AppKitReviewProposalVoteEvidenceView: NSView {
    var onHeightInvalidated: (() -> Void)?

    private let stack = NSStackView()
    private var findingID: String?
    private var presentation: PullRequestReviewVotePresentation?
    private var typography = TranscriptTypography()
    private var isExpanded = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        evidence: PullRequestReviewProposalRecord.CommentEvidence?,
        reviewers: [PullRequestReviewProposalRecord.Reviewer],
        typography: TranscriptTypography
    ) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let evidence else {
            findingID = nil
            presentation = nil
            isHidden = true
            return
        }
        configure(
            findingID: evidence.findingID,
            votes: evidence.votes,
            reviewers: evidence.reviewers ?? reviewers,
            typography: typography
        )
    }

    func configure(
        findingID: String,
        votes: [ReviewTeamVote],
        reviewers: [PullRequestReviewProposalRecord.Reviewer],
        typography: TranscriptTypography,
        initiallyExpanded: Bool = false
    ) {
        if self.findingID != findingID {
            isExpanded = initiallyExpanded
        }
        self.findingID = findingID
        presentation = PullRequestReviewVotePresentation(findingID: findingID, votes: votes, reviewers: reviewers)
        self.typography = typography
        rebuild()
    }
}

private extension AppKitReviewProposalVoteEvidenceView {
    func rebuild() {
        guard let presentation else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        isHidden = false
        let button = AppKitTranscriptHeaderToggleButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.font = typography.nsFont(.caption, weight: .medium)
        button.title = presentation.summary
        button.symbolName = isExpanded ? "chevron.up" : "chevron.down"
        button.target = self
        button.action = #selector(toggleDetails)
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(presentation.disclosureLabel(isExpanded: isExpanded))
        stack.addArrangedSubview(button)
        if isExpanded {
            for reviewer in presentation.reviewers {
                stack.addFullWidthArrangedSubview(voteSection(reviewer))
            }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(presentation.accessibilityLabel)
    }

    @objc
    func toggleDetails() {
        isExpanded.toggle()
        rebuild()
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
        onHeightInvalidated?()
    }

    func voteSection(_ reviewer: PullRequestReviewVotePresentation.Reviewer) -> NSView {
        let section = NSStackView()
        section.translatesAutoresizingMaskIntoConstraints = false
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 4
        section.addFullWidthArrangedSubview(voteHeader(title: reviewer.title, status: reviewer.status))
        section.addFullWidthArrangedSubview(label(reviewer.requestedModel, color: .secondaryLabelColor))
        if !reviewer.rationale.isEmpty {
            section.addFullWidthArrangedSubview(rationaleLabel(reviewer.rationale))
        }
        section.setAccessibilityElement(true)
        section.setAccessibilityRole(.group)
        section.setAccessibilityLabel(reviewer.accessibilityLabel)
        return section
    }

    func voteHeader(title: String, status: String) -> NSView {
        let titleField = label(title, color: .labelColor)
        titleField.font = typography.nsFont(.toolSummary, weight: .semibold)
        let statusField = label(status, color: .labelColor)
        statusField.font = typography.nsFont(.caption, weight: .semibold)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [titleField, spacer, statusField])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    func rationaleLabel(_ markdown: String) -> NSTextField {
        let field = label("", color: .labelColor)
        let font = typography.nsFont(.toolSummary)
        field.font = font
        let attributed = NSMutableAttributedString(attributedString: AppKitMarkdownInlineString.attributedString(
            for: markdown,
            baseFont: font,
            foregroundColor: .labelColor
        ))
        // The shared inline renderer truncates by default; a rationale must remain fully readable.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
        field.attributedStringValue = attributed
        field.setAccessibilityLabel(attributed.string)
        return field
    }

    func label(_ text: String, color: NSColor) -> NSTextField {
        AppKitTranscriptWidgetLabelFactory.label(
            text,
            level: .caption,
            color: color,
            typography: typography,
            wraps: true
        )
    }
}
