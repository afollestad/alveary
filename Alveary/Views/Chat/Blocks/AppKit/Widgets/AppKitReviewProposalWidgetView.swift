import AppKit

/// A review decision with its saved comment, staged threads, and editable verdict.
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
        var summaryBody: String = ""
        var summaryDocument: AppMarkdownDocument?
        var published: ReviewProposalWidgetState.Published?
    }

    var onConfirm: ((String, PullRequestReviewEvent) -> Void)?
    var onReject: ((String) -> Void)?
    var onSelectEvent: ((String, PullRequestReviewEvent) -> Void)?
    var onUpdateBody: ((String, String) -> Bool)?
    var onImmediateHeightInvalidated: (() -> Void)?
    /// Drops one of the review's staged comments, by its position in the stored envelope.
    var onRemoveComment: ((String, Int) -> Void)?
    var onJumpToComment: ((String, DiffCommentAnchor) -> Void)?
    var onOpenPullRequest: ((PullRequestIdentifier) -> Void)?
    /// A comment card's markdown body can change height after an inline image loads.
    var onHeightInvalidated: (() -> Void)?
    /// Kept off `Configuration`, which is `Equatable`: the loader is an actor, and it is constant
    /// for the app's lifetime, so it is identity rather than render input.
    var avatarLoader: GitHubAvatarLoader?
    /// Opens a link inside a pending comment's markdown body.
    var onOpenMarkdownLink: ((URL) -> Void)?
    /// A submitted card's comment Edit and Delete, by proposal id and then comment node id.
    var onEditPublishedComment: (@MainActor (String, String, String) async -> Bool)?
    var onDeletePublishedComment: ((String, String) -> Void)?

    private let stack = NSStackView()
    private let verdictControl = AppKitTranscriptApprovalSplitControl()
    private let diffView = AppKitReviewProposalDiffView()
    private let staleCommentsView = AppKitReviewProposalStaleCommentsView()
    private var configuration: Configuration?
    private var summaryView: AppKitReviewProposalSummaryView?
    private var publishedView: AppKitReviewProposalPublishedView?

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
        staleCommentsView.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        diffView.onOpenLink = { [weak self] url in
            self?.onOpenMarkdownLink?(url)
        }
        diffView.onJumpToProposedComment = { [weak self] anchor in
            guard let self, let proposalID = configuration?.presentation?.id else {
                return
            }
            onJumpToComment?(proposalID, anchor)
        }
        diffView.onRemoveProposedComment = { [weak self] index in
            guard let proposalID = self?.configuration?.presentation?.id else {
                return
            }
            self?.onRemoveComment?(proposalID, index)
        }
        staleCommentsView.onRemoveComment = { [weak self] index in
            guard let proposalID = self?.configuration?.presentation?.id else {
                return
            }
            self?.onRemoveComment?(proposalID, index)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasContent: Bool {
        stack.arrangedSubviews.contains { !$0.isHidden }
    }

    /// Widest row at its uncompressed size, so the shell can size to content. The actions row
    /// carries a flexible spacer, so measure its buttons instead.
    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { widest, row in
            // A rule spans whatever width the card has; it never asks for any.
            if row is AppKitHostToolWidgetDividerView {
                return widest
            }
            if let summary = row as? AppKitReviewProposalSummaryView {
                return max(widest, summary.naturalWidth)
            }
            if let published = row as? AppKitReviewProposalPublishedView {
                return max(widest, published.naturalWidth)
            }
            if let staleRow = row as? AppKitReviewProposalStaleCommentsView {
                return max(widest, min(staleRow.naturalWidth, Self.maximumDiffWidth))
            }
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
        let previous = self.configuration
        self.configuration = configuration
        let hadSummary = summaryView != nil
        updateSummary(configuration)
        // Only a rebuild places the other rows around the summary and rules it off, so mounting or
        // unmounting it takes one even if no other render input changed.
        if Self.needsBodyRebuild(previous, configuration) || hadSummary != (summaryView != nil) {
            rebuild(configuration)
        } else {
            updateVerdictControl(configuration)
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
        guard let configuration, let identifier = Self.pullRequestIdentifier(configuration) else {
            return
        }
        onOpenPullRequest?(identifier)
    }
}

private extension AppKitReviewProposalWidgetView {
    func updateSummary(_ configuration: Configuration) {
        let isInteractive = configuration.isInteractive && configuration.presentation != nil
        guard isInteractive || !configuration.summaryBody.isEmpty else {
            if let summaryView {
                stack.removeArrangedSubview(summaryView)
                summaryView.removeFromSuperview()
                self.summaryView = nil
            }
            return
        }
        if summaryView == nil {
            let summary = AppKitReviewProposalSummaryView()
            summary.onSave = { [weak self] id, body in self?.onUpdateBody?(id, body) ?? false }
            summary.onOpenLink = { [weak self] url in self?.onOpenMarkdownLink?(url) }
            summary.onHeightInvalidated = { [weak self] in self?.onImmediateHeightInvalidated?() }
            summary.onEditingChanged = { [weak self] in
                guard let self, let configuration = self.configuration else { return }
                updateVerdictControl(configuration)
            }
            summaryView = summary
            // Appended; `configure` follows a mount with `rebuild`, which places every other row around it.
            stack.addFullWidthArrangedSubview(summary)
        }
        summaryView?.isHidden = false
        summaryView?.configure(.init(
            proposalID: isInteractive ? configuration.presentation?.id : nil,
            markdown: configuration.summaryBody,
            document: configuration.summaryDocument,
            isEditable: isInteractive && !configuration.isSubmitting,
            typography: configuration.typography
        ))
    }

    /// The card reads top to bottom as its body (the comments it would publish, or published), then
    /// the top-level comment, then the controls that act on the whole review.
    func rebuild(_ configuration: Configuration) {
        // A mounted summary and published body stay put, so an open editor inside either keeps its focus.
        stack.arrangedSubviews.filter { $0 !== summaryView && ($0 !== publishedView || configuration.published == nil) }.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        diffView.removeFromSuperview()
        staleCommentsView.removeFromSuperview()
        if let published = configuration.published, let proposalID = configuration.content.proposalID {
            mountPublished(.init(proposalID: proposalID, published: published, typography: configuration.typography))
            addFooter([Self.buttonRow([openPullRequestButton(configuration)])])
            return
        }

        // Resolved cards keep only what happened; the controls and the diff belong to a decision
        // that is no longer open.
        guard configuration.isInteractive, configuration.presentation != nil else {
            Self.bannerLabels(configuration).forEach { stack.addFullWidthArrangedSubview($0) }
            applyRowSpacing(bodyEnd: nil)
            return
        }

        addPendingCommentSummary(configuration)
        addCollectiveCompletionWarning(configuration)
        addDiffPreview(configuration)
        addStaleComments(configuration)
        addFooter(Self.bannerLabels(configuration) + [actionRow(configuration)])
    }

    /// Body rows go in ahead of the top-level comment rather than after it, because `rebuild` keeps
    /// the summary mounted: re-adding it would end an open editing session, and changing the verdict
    /// mid-edit rebuilds the card.
    func addAboveSummary(_ view: NSView) {
        guard let summaryView, let index = stack.arrangedSubviews.firstIndex(of: summaryView) else {
            return stack.addFullWidthArrangedSubview(view)
        }
        stack.insertFullWidthArrangedSubview(view, at: index)
    }

    /// Ends the card with `rows` under the top-level comment, ruled off from it when there is one.
    func addFooter(_ rows: [NSView]) {
        let bodyEnd = stack.arrangedSubviews.last { $0 !== summaryView }
        if summaryView != nil {
            stack.addFullWidthArrangedSubview(AppKitHostToolWidgetDividerView())
        }
        rows.forEach { stack.addFullWidthArrangedSubview($0) }
        applyRowSpacing(bodyEnd: bodyEnd)
    }

    /// Every row's spacing, set explicitly because the diff, stale list, summary, and published body
    /// are reused across rebuilds and would otherwise keep a clearance from a layout they no longer end.
    ///
    /// `bodyEnd` gets `footerSeparation`: the diff preview is a slab of tinted rows, and at the
    /// ordinary spacing the comment under it reads as a reply to its last inline comment rather than
    /// as the review's own.
    func applyRowSpacing(bodyEnd: NSView?) {
        let rows = stack.arrangedSubviews
        for (index, row) in rows.enumerated() {
            let next = rows.indices.contains(index + 1) ? rows[index + 1] : nil
            let spacing = if row === bodyEnd {
                Self.footerSeparation
            } else if next is AppKitHostToolWidgetDividerView {
                Self.footerDividerSpacingAbove
            } else if row is AppKitHostToolWidgetDividerView {
                Self.footerDividerSpacingBelow
            } else {
                NSStackView.useDefaultSpacing
            }
            stack.setCustomSpacing(spacing, after: row)
        }
    }

    func mountPublished(_ configuration: AppKitReviewProposalPublishedView.Configuration) {
        let view = publishedView ?? makePublishedView()
        view.avatarLoader = avatarLoader
        view.configure(configuration)
        if view.superview == nil { addAboveSummary(view) }
    }

    func makePublishedView() -> AppKitReviewProposalPublishedView {
        let view = AppKitReviewProposalPublishedView()
        view.onEditComment = { [weak self] id, nodeID, body in await self?.onEditPublishedComment?(id, nodeID, body) ?? false }
        view.onDeleteComment = { [weak self] id, nodeID in self?.onDeletePublishedComment?(id, nodeID) }
        view.onJumpToComment = { [weak self] id, anchor in self?.onJumpToComment?(id, anchor) }
        view.onOpenLink = { [weak self] url in self?.onOpenMarkdownLink?(url) }
        view.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        view.onImmediateHeightInvalidated = { [weak self] in self?.onImmediateHeightInvalidated?() }
        publishedView = view
        return view
    }

    func addCollectiveCompletionWarning(_ configuration: Configuration) {
        guard let warning = configuration.presentation?.collectiveCompletionWarning else { return }
        let label = AppKitTranscriptWidgetLabelFactory.label(
            warning, level: .caption, color: .labelColor, typography: configuration.typography, wraps: true
        )
        label.setAccessibilityLabel(warning)
        addAboveSummary(label)
    }

    /// Under the diff, because these are the comments it could not draw. Confirm refuses while any
    /// remain, so the list is also the route to clearing them.
    func addStaleComments(_ configuration: Configuration) {
        guard case .loaded(let preview) = configuration.preview, !preview.staleComments.isEmpty else {
            return
        }
        staleCommentsView.configure(
            AppKitReviewProposalStaleCommentsView.Configuration(
                comments: preview.staleComments,
                allowsRemoval: !configuration.isSubmitting,
                reviewers: configuration.presentation?.reviewers ?? [],
                typography: configuration.typography
            )
        )
        addAboveSummary(staleCommentsView)
    }

    func addPendingCommentSummary(_ configuration: Configuration) {
        let text: String
        switch configuration.preview {
        case .loading, nil:
            text = "Loading the comments this review would publish…"
        case .failed:
            let total = Self.fallbackCommentTotal(configuration)
            text = total > 0
                ? "Publishes \(total) review comment\(total == 1 ? "" : "s")."
                : Self.noInlineCommentsSummary
        case .loaded(let preview):
            text = Self.loadedCommentSummary(preview)
        }
        addAboveSummary(
            AppKitTranscriptWidgetLabelFactory.label(
                text,
                level: .caption,
                color: .secondaryLabelColor,
                typography: configuration.typography,
                wraps: true
            )
        )
    }

    /// The pending comments on the lines they were written against. The only control on them is
    /// Remove, which edits the stored envelope — nothing here can post to GitHub before the user
    /// confirms. A submission in flight is already publishing what it was handed, so it withdraws
    /// even that.
    func addDiffPreview(_ configuration: Configuration) {
        // `files`, not `isEmpty`: a review whose every comment went stale still has a list to show
        // below, and mounting the diff view with nothing to draw would add only its spacing.
        guard case .loaded(let preview) = configuration.preview, !preview.files.isEmpty else {
            return
        }
        // Before `configure`, which skips an unchanged preview and would leave the cards without it.
        diffView.avatarLoader = avatarLoader
        diffView.configure(.init(
            preview: preview,
            typography: configuration.typography,
            allowsRemoval: !configuration.isSubmitting,
            // A preview only loads for the conversation that opened the proposal — another
            // conversation's copy renders read-only with no presentation and no diff — so
            // reaching here means there is a proposal to jump into.
            allowsJumping: true,
            evidenceByProposedIndex: Dictionary(
                uniqueKeysWithValues: (configuration.presentation?.comments ?? []).enumerated().compactMap { index, comment in
                    comment.evidence.map { (index, $0) }
                }
            ),
            reviewers: configuration.presentation?.reviewers ?? []
        ))
        addAboveSummary(diffView)
    }

    /// One split button carries both halves of the decision: the primary submits the selected
    /// verdict, and the menu only changes which verdict that is.
    func updateVerdictControl(_ configuration: Configuration) {
        let selected = configuration.selectedEvent ?? configuration.content.event
        let title = configuration.isSubmitting ? "Submitting…" : Self.verdictLabel(selected)
        verdictControl.setLabel(title, forSegment: 0)
        verdictControl.primaryIcon = Self.verdictIcon(selected)
        // The face shows only the verdict, so the spoken label names the whole action.
        verdictControl.setAccessibilityLabel("Submit review: \(Self.verdictLabel(selected))")
        // Only the primary half refuses an unsubmittable verdict; the menu stays live so a viewer
        // reviewing their own pull request can still switch to the verdict GitHub does allow.
        verdictControl.isEnabled = !configuration.isSubmitting
        verdictControl.setEnabled(
            configuration.canSubmit && summaryView?.isEditing != true && !Self.isSelfReviewVerdict(selected, configuration),
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
            item.isEnabled = !Self.isSelfReviewVerdict(event, configuration)
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
        let reject = Self.button(
            title: "Cancel",
            icon: .system("xmark"),
            style: .secondary,
            target: self,
            action: #selector(handleReject)
        )
        reject.isEnabled = !configuration.isSubmitting

        updateVerdictControl(configuration)

        return Self.buttonRow([reject, openPullRequestButton(configuration), verdictControl])
    }

    /// Shared by the pending card's action row and the submitted card's footer.
    func openPullRequestButton(_ configuration: Configuration) -> NSView {
        let open = Self.button(
            title: "Open PR",
            icon: .octicon(.pullRequest16),
            style: .secondary,
            target: self,
            action: #selector(handleOpenPullRequest)
        )
        open.isEnabled = Self.pullRequestIdentifier(configuration) != nil
        return open
    }
}
