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
    /// A comment card's markdown body can change height after an inline image loads.
    var onHeightInvalidated: (() -> Void)?
    /// Kept off `Configuration`, which is `Equatable`: the loader is an actor, and it is constant
    /// for the app's lifetime, so it is identity rather than render input.
    var avatarLoader: GitHubAvatarLoader?
    /// Opens a link inside a pending comment's markdown body.
    var onOpenMarkdownLink: ((URL) -> Void)?

    private let stack = NSStackView()
    private let verdictControl = AppKitTranscriptApprovalSplitControl()
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
        verdictControl.segmentCount = 2
        verdictControl.trackingMode = .momentary
        verdictControl.controlSize = .small
        verdictControl.actionStyle = .primary
        verdictControl.target = self
        verdictControl.action = #selector(handleVerdictControl)
        diffView.onHeightInvalidated = { [weak self] in
            self?.onHeightInvalidated?()
        }
        diffView.onOpenLink = { [weak self] url in
            self?.onOpenMarkdownLink?(url)
        }
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
            // The split control is an `NSSegmentedControl`, not a button; missing it here would
            // under-size the card by the whole submit control.
            let buttons = rowStack.arrangedSubviews.filter {
                $0 is AppKitTranscriptApprovalButton || $0 is AppKitTranscriptApprovalSplitControl
            }
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

    /// Leading glyph naming the verdict the primary half would submit.
    static func verdictSymbolName(_ event: PullRequestReviewEvent) -> String {
        switch event {
        case .approve:
            "checkmark"
        case .requestChanges:
            "exclamationmark.circle"
        case .comment:
            "bubble.left"
        }
    }

    @objc
    private func handleVerdictControl() {
        switch verdictControl.selectedSegment {
        case 0:
            handleConfirm()
        case 1:
            showVerdictMenu()
        default:
            break
        }
    }

    @objc
    private func handleVerdictMenuItem(_ item: NSMenuItem) {
        guard let proposalID = configuration?.presentation?.id,
              item.tag >= 0,
              item.tag < Self.selectableEvents.count else {
            return
        }
        onSelectEvent?(proposalID, Self.selectableEvents[item.tag])
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
    private func handleOpenPullRequest() {
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
        stack.addFullWidthArrangedSubview(actionRow(configuration))
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
        // Before `configure`, which skips an unchanged preview and would leave the cards without it.
        diffView.avatarLoader = avatarLoader
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

    /// GitHub rejects approving or requesting changes on your own pull request, so the card refuses
    /// them rather than letting a confirmation fail at submission.
    func isSelfReviewVerdict(_ event: PullRequestReviewEvent, _ configuration: Configuration) -> Bool {
        let viewerIsAuthor = configuration.preview?.loadedPreview?.viewerIsAuthor ?? false
        return viewerIsAuthor && (event == .approve || event == .requestChanges)
    }

    /// One split button carries both halves of the decision: the primary submits the selected
    /// verdict, and the menu only changes which verdict that is.
    func updateVerdictControl(_ configuration: Configuration) {
        let selected = configuration.selectedEvent ?? configuration.content.event
        let title = configuration.isSubmitting ? "Submitting…" : Self.verdictLabel(selected)
        verdictControl.setLabel(title, forSegment: 0)
        verdictControl.primarySymbolName = Self.verdictSymbolName(selected)
        // The face shows only the verdict, so the spoken label names the whole action.
        verdictControl.setAccessibilityLabel("Submit review: \(Self.verdictLabel(selected))")
        // Only the primary half refuses an unsubmittable verdict; the menu stays live so a viewer
        // reviewing their own pull request can still switch to the verdict GitHub does allow.
        verdictControl.isEnabled = !configuration.isSubmitting
        verdictControl.setEnabled(
            configuration.canSubmit && !isSelfReviewVerdict(selected, configuration),
            forSegment: 0
        )
        verdictControl.setEnabled(true, forSegment: 1)
        // Segment widths are what make a click resolve to the right half, not just chrome.
        verdictControl.setWidth(verdictControl.preferredContentWidth, forSegment: 0)
        verdictControl.setWidth(AppKitTranscriptApprovalSplitControl.menuWidth, forSegment: 1)
    }

    func showVerdictMenu() {
        guard let configuration else {
            return
        }
        let selected = configuration.selectedEvent ?? configuration.content.event
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, event) in Self.selectableEvents.enumerated() {
            let item = NSMenuItem(
                title: Self.verdictLabel(event),
                action: #selector(handleVerdictMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = event == selected ? .on : .off
            item.isEnabled = !isSelfReviewVerdict(event, configuration)
            menu.addItem(item)
        }
        // Anchored in the control's own space; this view is Auto Layout, so a parent-frame origin
        // would drift with the row's packing.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: verdictControl.bounds.maxY + 2),
            in: verdictControl
        )
    }

    func actionRow(_ configuration: Configuration) -> NSView {
        let reject = button(title: "Cancel", style: .secondary, action: #selector(handleReject))
        reject.isEnabled = !configuration.isSubmitting

        let open = button(title: "Open PR", style: .secondary, action: #selector(handleOpenPullRequest))
        open.isEnabled = (configuration.presentation?.identifier ?? configuration.content.identifier) != nil

        updateVerdictControl(configuration)

        let row = NSStackView(views: [reject, open, verdictControl])
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
