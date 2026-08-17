import AppKit

/// The staged comments the pull request's current diff cannot place, listed under the preview.
///
/// A comment is anchored to a line validated at propose time; later commits move those lines, and
/// the diff is the one surface that cannot draw an anchor matching nothing. The pane already
/// answers this for GitHub's own threads — `PullRequestReviewThreadView` gives an outdated thread
/// an orange pill, drops its jump affordance, and falls back to naming the file alone — so this
/// gives a staged comment the same treatment rather than inventing a second vocabulary.
///
/// Listing them is what keeps the card honest: the summary counts every staged comment, so a
/// silently dropped one made the card promise more than it drew.
@MainActor
final class AppKitReviewProposalStaleCommentsView: NSView {
    struct Configuration: Equatable {
        let comments: [PullRequestReviewProposalPreview.StaleComment]
        /// A submission in flight is already publishing what it was handed, so Remove withdraws.
        let allowsRemoval: Bool
        let typography: TranscriptTypography
    }

    /// Drops one staged comment by its position in the stored envelope.
    var onRemoveComment: ((Int) -> Void)?

    private let stack = NSStackView()
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { max($0, ceil($1.fittingSize.width)) }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !configuration.comments.isEmpty else {
            return
        }
        stack.addFullWidthArrangedSubview(Self.caption(configuration))
        for comment in configuration.comments {
            stack.addFullWidthArrangedSubview(row(for: comment, configuration: configuration))
        }
    }
}

private extension AppKitReviewProposalStaleCommentsView {
    /// Says what happened and what it means, because a count alone reads as an error the user
    /// caused. The remedy — remove, or ask for a fresh review — belongs to the confirm refusal.
    static func caption(_ configuration: Configuration) -> NSTextField {
        let count = configuration.comments.count
        return AppKitTranscriptWidgetLabelFactory.label(
            count == 1
                ? "1 comment no longer matches the diff and will not be published."
                : "\(count) comments no longer match the diff and will not be published.",
            level: .caption,
            color: .secondaryLabelColor,
            typography: configuration.typography,
            wraps: true
        )
    }

    func row(
        for comment: PullRequestReviewProposalPreview.StaleComment,
        configuration: Configuration
    ) -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 2
        container.addFullWidthArrangedSubview(header(for: comment, configuration: configuration))
        container.addFullWidthArrangedSubview(body(for: comment, configuration: configuration))
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        // No line to name — that is the whole point — so the label says the file and the reason.
        container.setAccessibilityLabel("Outdated comment on \(comment.path)")
        return container
    }

    /// Inline markdown, the way the shell renders its author-written detail line — the body is a
    /// review comment, and showing its backticks and asterisks raw would read as a glitch.
    func body(
        for comment: PullRequestReviewProposalPreview.StaleComment,
        configuration: Configuration
    ) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        let font = configuration.typography.nsFont(.caption)
        field.font = font
        field.attributedStringValue = AppKitMarkdownInlineString.attributedString(
            for: comment.bodyMarkdown,
            baseFont: font,
            foregroundColor: .secondaryLabelColor,
            inlineCodeFill: AppKitMarkdownInlineString.mutedInlineCodeFill(over: .secondaryLabelColor)
        )
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func header(
        for comment: PullRequestReviewProposalPreview.StaleComment,
        configuration: Configuration
    ) -> NSView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        let captionSize = configuration.typography.size(for: .caption)

        let path = AppKitTranscriptWidgetLabelFactory.label(
            comment.path,
            level: .caption,
            color: .labelColor,
            typography: configuration.typography
        )
        path.lineBreakMode = .byTruncatingMiddle
        row.addArrangedSubview(path)

        let badge = AppKitPullRequestCommentBadgeView()
        // The pane's own outdated tint, and the same one "Proposed" already wears on this card —
        // both mean unpublished-and-needs-attention rather than two different warnings.
        badge.configure(
            title: "Outdated",
            style: .tinted(AppKitPullRequestCommentBadgeView.pendingTint),
            fontSize: captionSize
        )
        badge.setAccessibilityLabel("Outdated: this comment's line is gone from the diff")
        row.addArrangedSubview(badge)

        row.addArrangedSubview(NSView())
        if configuration.allowsRemoval {
            let menu = AppKitReviewProposalCommentMenuButton()
            menu.configure(fontSize: captionSize)
            menu.onDelete = { [weak self] in
                self?.onRemoveComment?(comment.proposedIndex)
            }
            row.addArrangedSubview(menu)
        }
        for view in [path, badge] {
            view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }
}
