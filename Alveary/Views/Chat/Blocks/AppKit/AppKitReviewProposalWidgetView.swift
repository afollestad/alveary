import AppKit

/// Everything a review-proposal card needs from `PullRequestReviewProposalCoordinator`, resolved
/// per render because confirmation state lives outside the provider turn.
struct ReviewProposalWidgetState: Equatable {
    let presentation: PullRequestReviewProposalPresentation?
    let preview: PullRequestReviewProposalPreviewState?
    let selectedEvent: PullRequestReviewEvent?
    let canSubmit: Bool
    let isSubmitting: Bool
    let errorMessage: String?

    init(
        presentation: PullRequestReviewProposalPresentation? = nil,
        preview: PullRequestReviewProposalPreviewState? = nil,
        selectedEvent: PullRequestReviewEvent? = nil,
        canSubmit: Bool = false,
        isSubmitting: Bool = false,
        errorMessage: String? = nil
    ) {
        self.presentation = presentation
        self.preview = preview
        self.selectedEvent = selectedEvent
        self.canSubmit = canSubmit
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
    }
}

/// Body for `propose_pr_review`: the verdict the user is about to submit, the pending comments it
/// would publish shown on their diff lines, and the confirm/reject decision.
///
/// Unlike the scheduling proposal beside it, confirming here awaits GitHub, so the row carries a
/// submitting state; and unlike every other host-tool card, its verdict is editable — the model
/// proposes, the user decides.
@MainActor
final class AppKitReviewProposalWidgetView: NSView {
    struct Configuration: Equatable {
        let content: PullRequestReviewProposalWidgetContent
        let presentation: PullRequestReviewProposalPresentation?
        let preview: PullRequestReviewProposalPreviewState?
        let selectedEvent: PullRequestReviewEvent?
        let canSubmit: Bool
        let isInteractive: Bool
        let isSubmitting: Bool
        let outcome: HostToolWidgetOutcome?
        let errorMessage: String?
        let typography: TranscriptTypography
    }

    var onConfirm: ((String, PullRequestReviewEvent) -> Void)?
    var onReject: ((String) -> Void)?
    var onSelectEvent: ((String, PullRequestReviewEvent) -> Void)?
    var onOpenPullRequest: ((PullRequestIdentifier) -> Void)?

    private let stack = NSStackView()
    private let verdictControl = NSSegmentedControl()
    private let diffView = AppKitReviewProposalDiffView()
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        verdictControl.translatesAutoresizingMaskIntoConstraints = false
        verdictControl.segmentStyle = .rounded
        verdictControl.trackingMode = .selectOne
        verdictControl.target = self
        verdictControl.action = #selector(handleVerdictChange)
        verdictControl.segmentCount = Self.selectableEvents.count
        for (index, event) in Self.selectableEvents.enumerated() {
            verdictControl.setLabel(Self.verdictLabel(event), forSegment: index)
        }
        // The segments name the choices; this names what is being chosen.
        verdictControl.setAccessibilityLabel("Review verdict")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    /// Widest row at its uncompressed size, so the shell can size to content. The actions row
    /// carries a flexible spacer, so measure its buttons instead.
    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { widest, row in
            if let diffRow = row as? AppKitReviewProposalDiffView {
                // A diff line's natural width is its longest line, which would blow past the
                // bubble cap; the shell clamps, and the rows truncate rather than widen the card.
                return max(widest, min(diffRow.naturalWidth, Self.maximumDiffWidth))
            }
            guard let rowStack = row as? NSStackView else {
                return max(widest, ceil(row.fittingSize.width))
            }
            let buttons = rowStack.arrangedSubviews.filter { $0 is AppKitTranscriptApprovalButton }
            guard !buttons.isEmpty else {
                return max(widest, ceil(row.fittingSize.width))
            }
            let spacing = rowStack.spacing * CGFloat(buttons.count - 1)
            let width = buttons.reduce(CGFloat.zero) { $0 + ceil($1.fittingSize.width) } + spacing
            return max(widest, width)
        }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        rebuild(configuration)
    }

    static let selectableEvents: [PullRequestReviewEvent] = [.approve, .requestChanges, .comment]
    /// Past this the card is sized by one long code line rather than by its controls.
    static let maximumDiffWidth: CGFloat = 560

    static func verdictLabel(_ event: PullRequestReviewEvent) -> String {
        switch event {
        case .approve:
            "Approve"
        case .requestChanges:
            "Request changes"
        case .comment:
            "Comment"
        }
    }

    @objc
    private func handleVerdictChange() {
        guard let proposalID = configuration?.presentation?.id,
              verdictControl.selectedSegment >= 0,
              verdictControl.selectedSegment < Self.selectableEvents.count else {
            return
        }
        onSelectEvent?(proposalID, Self.selectableEvents[verdictControl.selectedSegment])
    }

    @objc
    private func handleConfirm() {
        guard let proposalID = configuration?.presentation?.id,
              let event = configuration?.selectedEvent ?? configuration?.content.event else {
            return
        }
        onConfirm?(proposalID, event)
    }

    @objc
    private func handleReject() {
        guard let proposalID = configuration?.presentation?.id else {
            return
        }
        onReject?(proposalID)
    }

    @objc
    private func handleReview() {
        guard let identifier = configuration?.presentation?.identifier
            ?? configuration?.content.identifier else {
            return
        }
        onOpenPullRequest?(identifier)
    }
}

private extension AppKitReviewProposalWidgetView {
    func rebuild(_ configuration: Configuration) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        diffView.removeFromSuperview()

        // Resolved cards keep only what happened; the controls and the diff belong to a decision
        // that is no longer open.
        guard configuration.isInteractive, configuration.presentation != nil else {
            addBanners(configuration)
            return
        }

        addPendingCommentSummary(configuration)
        addDiffPreview(configuration)
        addBanners(configuration)
        stack.addFullWidthArrangedSubview(verdictRow(configuration))
        if let actions = actionRow(configuration) {
            stack.addFullWidthArrangedSubview(actions)
        }
    }

    func addPendingCommentSummary(_ configuration: Configuration) {
        let count = configuration.preview?.loadedPreview?.pendingCommentCount
            ?? configuration.presentation?.pendingCommentCount
            ?? configuration.content.pendingCommentCount
            ?? 0
        let text: String
        switch configuration.preview {
        case .loading, nil:
            text = "Loading the comments this review would publish…"
        case .failed:
            text = count > 0
                ? "Publishes \(count) pending review comment\(count == 1 ? "" : "s")."
                : "Publishes the review summary only."
        case .loaded(let preview):
            if preview.pendingCommentCount == 0 {
                text = "Publishes the review summary only — no inline comments are pending."
            } else {
                var summary = "Publishes \(preview.pendingCommentCount) pending review comment" +
                    "\(preview.pendingCommentCount == 1 ? "" : "s")."
                if preview.hiddenFileCount > 0 {
                    summary += " \(preview.hiddenFileCount) more file" +
                        "\(preview.hiddenFileCount == 1 ? "" : "s") not shown; open the pull request to read them all."
                }
                text = summary
            }
        }
        stack.addFullWidthArrangedSubview(
            AppKitTranscriptWidgetLabelFactory.label(
                text,
                level: .caption,
                color: .secondaryLabelColor,
                typography: configuration.typography,
                wraps: true
            )
        )
    }

    /// The pending comments on the lines they were written against, read-only: the card carries
    /// no comment interaction, so nothing in it can post to GitHub before the user confirms.
    func addDiffPreview(_ configuration: Configuration) {
        guard case .loaded(let preview) = configuration.preview, !preview.isEmpty else {
            return
        }
        diffView.configure(preview: preview, typography: configuration.typography)
        stack.addFullWidthArrangedSubview(diffView)
    }

    func addBanners(_ configuration: Configuration) {
        for message in bannerMessages(configuration) {
            stack.addFullWidthArrangedSubview(
                AppKitTranscriptWidgetLabelFactory.label(
                    message,
                    level: .caption,
                    color: .systemRed,
                    typography: configuration.typography,
                    wraps: true
                )
            )
        }
    }

    func bannerMessages(_ configuration: Configuration) -> [String] {
        var messages: [String] = []
        if configuration.isInteractive, let errorMessage = configuration.errorMessage {
            messages.append(errorMessage)
        }
        if case .failed(let message) = configuration.preview, configuration.isInteractive {
            messages.append("Could not load the review's comments: \(message)")
        }
        if configuration.content.status == .failed, let message = configuration.content.message {
            messages.append(message)
        }
        return messages
    }

    func verdictRow(_ configuration: Configuration) -> NSView {
        let selected = configuration.selectedEvent ?? configuration.content.event
        verdictControl.selectedSegment = Self.selectableEvents.firstIndex(of: selected) ?? 0
        let viewerIsAuthor = configuration.preview?.loadedPreview?.viewerIsAuthor ?? false
        for (index, event) in Self.selectableEvents.enumerated() {
            // GitHub rejects approving or requesting changes on your own pull request, so the
            // card refuses them rather than letting a confirmation fail at submission.
            let isSelfReviewVerdict = viewerIsAuthor && (event == .approve || event == .requestChanges)
            verdictControl.setEnabled(!configuration.isSubmitting && !isSelfReviewVerdict, forSegment: index)
        }
        let row = NSStackView(views: [verdictControl])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    func actionRow(_ configuration: Configuration) -> NSView? {
        let review = button(title: "Review…", style: .secondary, action: #selector(handleReview))
        review.isEnabled = (configuration.presentation?.identifier ?? configuration.content.identifier) != nil

        let reject = button(title: "Cancel", style: .secondary, action: #selector(handleReject))
        reject.isEnabled = !configuration.isSubmitting

        let confirm = button(
            title: configuration.isSubmitting ? "Submitting…" : "Submit review",
            style: .primary,
            action: #selector(handleConfirm)
        )
        confirm.isEnabled = !configuration.isSubmitting && configuration.canSubmit

        let row = NSStackView(views: [review, reject, confirm])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    func button(
        title: String,
        style: AppKitTranscriptApprovalButtonStyle,
        action: Selector
    ) -> AppKitTranscriptApprovalButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = title
        button.actionStyle = style
        button.target = self
        button.action = action
        return button
    }
}

private extension PullRequestReviewProposalPreviewState {
    var loadedPreview: PullRequestReviewProposalPreview? {
        guard case .loaded(let preview) = self else {
            return nil
        }
        return preview
    }
}

private extension Optional where Wrapped == PullRequestReviewProposalPreviewState {
    var loadedPreview: PullRequestReviewProposalPreview? {
        self?.loadedPreview
    }
}
