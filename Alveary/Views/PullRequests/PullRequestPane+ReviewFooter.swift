import SwiftUI

/// The pending-batch review footer: shows the queued inline-comment count and an
/// expandable summary composer for submitting the whole review in one call.
struct PullRequestPaneReviewFooter: View {
    let viewModel: PullRequestsViewModel
    let session: PullRequestPaneSession

    @State private var isExpanded: Bool
    @State private var selectedEvent = PullRequestReviewEvent.comment
    /// Nil takes the default action; a stale pick falls back the same way.
    @State private var selectedStateKind: PullRequestStateAction.Kind?
    /// BlockInputKit store for the overall comment; created when the composer
    /// expands, serialized back into the pending draft on collapse or submit.
    @State private var overallDraft: PullRequestCommentDraftBox?

    init(
        viewModel: PullRequestsViewModel,
        session: PullRequestPaneSession,
        initiallyExpanded: Bool = false
    ) {
        self.viewModel = viewModel
        self.session = session
        _isExpanded = State(initialValue: initiallyExpanded)
        // Production expands through the button, which seeds the draft; snapshots
        // mount pre-expanded and need the editor present from the first render.
        _overallDraft = State(
            initialValue: initiallyExpanded
                ? PullRequestCommentDraftBox(markdown: session.pendingReview.overallComment)
                : nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = session.pendingReview.submissionError {
                InlineBanner(message: error, severity: .error, autoDismissAfter: nil, onDismiss: nil)
            }

            if let error = session.stateChangeError {
                InlineBanner(
                    message: error,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: viewModel.clearPullRequestStateChangeError
                )
            }

            if isExpanded {
                summaryComposer
            }

            footerNotes

            actionRow
        }
        .pullRequestAttachmentDropTarget(
            isEnabled: isExpanded && viewModel.supportsAttachmentUploads && !isUploading,
            onDrop: attach
        )
        .contextualPaneFooterChrome()
    }

    /// GitHub rejects Approve and Request changes on your own pull request, so
    /// they only appear for other people's PRs; your own submit as a comment.
    private var allowsVerdictEvents: Bool {
        guard let summary = session.summary else {
            // An identifier-opened pane knows nothing about authorship until its
            // first detail lands; withhold the verdicts rather than offer one
            // GitHub would reject. `effectiveEvent` demotes a stale selection.
            return false
        }
        if summary.isAuthored {
            return false
        }
        if let detail = session.detail, let viewer = detail.viewerLogin {
            return viewer != detail.authorLogin
        }
        return true
    }

    private var summaryComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allowsVerdictEvents {
                Picker("Review action", selection: $selectedEvent) {
                    Text("Comment").tag(PullRequestReviewEvent.comment)
                    Text("Approve").tag(PullRequestReviewEvent.approve)
                    Text("Request changes").tag(PullRequestReviewEvent.requestChanges)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Review action")
            }

            if let overallDraft {
                PullRequestCommentEditor(
                    draft: overallDraft,
                    placeholder: "Leave a comment",
                    onSubmit: submitIfAllowed,
                    onCancel: cancelComposer
                )
                .accessibilityLabel("Review summary comment")
            }
        }
    }

    /// Validation reads the live editor's emptiness instead of the last-serialized
    /// draft text, so Submit enables while typing without per-keystroke encoding.
    private var draftForValidation: PendingReviewDraft {
        var draft = session.pendingReview
        if let overallDraft {
            draft.overallComment = overallDraft.isEffectivelyEmpty ? "" : "-"
        }
        return draft
    }

    /// Keeps the typed summary when the composer collapses without submitting.
    private func serializeOverallComment() {
        if let overallDraft {
            viewModel.updateOverallReviewComment(overallDraft.markdown)
        }
    }

    /// Shared by the Cancel button and the editor's Escape key.
    private func cancelComposer() {
        guard !session.pendingReview.isSubmitting else {
            return
        }
        serializeOverallComment()
        overallDraft = nil
        isExpanded = false
    }

    /// A stale verdict selection cannot leak through when authorship gating
    /// hides the picker (e.g. the detail resolves the viewer as the author
    /// after Approve was already selected).
    private var effectiveEvent: PullRequestReviewEvent {
        allowsVerdictEvents ? selectedEvent : .comment
    }

    private var isUploading: Bool {
        viewModel.isUploadingAttachments(to: .reviewSummary)
    }

    /// Inline comments live on GitHub now, so the count comes from the detail.
    private var pendingCommentCount: Int {
        session.detail?.pendingCommentCount ?? 0
    }

    /// Submitting mid-upload would post the review without the attachment's link.
    private var canSubmit: Bool {
        !session.pendingReview.isSubmitting
            && !isUploading
            && PullRequestsViewModel.canSubmitReview(
                event: effectiveEvent,
                draft: draftForValidation,
                pendingCommentCount: pendingCommentCount
            )
    }

    private func attach(_ files: [URL]) {
        guard let overallDraft else {
            return
        }
        viewModel.attachFiles(files, to: .reviewSummary, draft: overallDraft)
    }

    /// Shared by the Submit button and the editor's Cmd+Return shortcut so the
    /// shortcut cannot bypass the button's enablement.
    private func submitIfAllowed() {
        guard canSubmit else {
            return
        }
        serializeOverallComment()
        Task {
            if await viewModel.submitReview(event: effectiveEvent) {
                overallDraft = nil
                isExpanded = false
            }
        }
    }

    /// The pending-comment count and any reason the state action is dead. Both
    /// sit above the buttons: the collapsed row splits its width evenly between
    /// the two actions, leaving no room for a leading label.
    @ViewBuilder
    private var footerNotes: some View {
        let count = pendingCommentCount
        if count > 0 {
            Text("\(count) pending comment\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !isExpanded, let note = effectiveStateAction?.disabledNote {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// While the detail is unavailable the row still shows its even split, with
    /// a disabled stand-in titled from the list row's known status — otherwise
    /// the footer paints a lone trailing button and snaps once the detail lands.
    /// An identifier-opened pane has no status to title one with until then.
    private var stateActions: [PullRequestStateAction] {
        guard session.detail != nil else {
            guard let status = session.summary?.status else {
                return []
            }
            return PullRequestStateAction.placeholder(for: status).map { [$0] } ?? []
        }
        return PullRequestStateAction.available(for: session.detail)
    }

    /// The selection falls back to the default whenever it no longer matches an
    /// available action — which is what retires "Mark ready for review" the
    /// moment the pull request leaves draft. Same guard as `effectiveEvent`.
    private var effectiveStateAction: PullRequestStateAction? {
        let actions = stateActions
        return actions.first { $0.kind == selectedStateKind } ?? actions.first
    }

    @ViewBuilder
    private var actionRow: some View {
        if isExpanded {
            composingActionRow
        } else if let action = effectiveStateAction {
            // Two equal halves, matching the other detail panes' footers.
            HStack(spacing: ContextualPaneLayout.actionSpacing) {
                stateActionButton(action, in: stateActions)
                    .frame(minWidth: ContextualPaneLayout.minimumHorizontalActionWidth, maxWidth: .infinity)
                startReviewButton(expandsHorizontally: true)
                    .frame(minWidth: ContextualPaneLayout.minimumHorizontalActionWidth, maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                startReviewButton(expandsHorizontally: false)
            }
        }
    }

    private var composingActionRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if viewModel.supportsAttachmentUploads {
                PullRequestCommentAttachButton(isUploading: isUploading, onPick: attach)
            }

            Button("Cancel", action: cancelComposer)
                .secondaryActionButtonStyle()
                .disabled(session.pendingReview.isSubmitting)

            Button(submitTitle) {
                submitIfAllowed()
            }
            .primaryActionButtonStyle()
            .disabled(!canSubmit)
        }
    }

    private func startReviewButton(expandsHorizontally: Bool) -> some View {
        Button("Submit review...") {
            overallDraft = PullRequestCommentDraftBox(
                markdown: viewModel.activePaneSession?.pendingReview.overallComment ?? ""
            )
            isExpanded = true
        }
        .primaryActionButtonStyle(expandsHorizontally: expandsHorizontally)
    }

    /// A single available action stays a plain button; more than one becomes the
    /// shared split button, whose menu selects (never runs) the other action.
    @ViewBuilder
    private func stateActionButton(
        _ action: PullRequestStateAction,
        in actions: [PullRequestStateAction]
    ) -> some View {
        if actions.count > 1 {
            SplitActionButton(
                title: action.title,
                emphasis: action.isDestructive ? .destructive : .secondary,
                expandsHorizontally: true,
                selectedOption: action.kind,
                options: actions.map(\.kind),
                optionTitle: { kind in actions.first { $0.kind == kind }?.title ?? "" },
                action: { run(action) },
                selectOption: { selectedStateKind = $0 }
            )
            .disabled(!action.isEnabled || session.isChangingState)
            .help(action.disabledNote ?? action.title)
        } else {
            plainStateActionButton(action)
        }
    }

    @ViewBuilder
    private func plainStateActionButton(_ action: PullRequestStateAction) -> some View {
        let button = Button(action.title) {
            run(action)
        }
        .disabled(!action.isEnabled || session.isChangingState)
        .help(action.disabledNote ?? action.title)

        if action.isDestructive {
            button.destructiveActionButtonStyle(expandsHorizontally: true)
        } else {
            button.secondaryActionButtonStyle(expandsHorizontally: true)
        }
    }

    private func run(_ action: PullRequestStateAction) {
        switch action.kind {
        case .close:
            viewModel.setPullRequestClosed(true)
        case .reopen:
            viewModel.setPullRequestClosed(false)
        case .markReady:
            viewModel.markPullRequestReadyForReview()
        case .markDraft:
            viewModel.convertPullRequestToDraft()
        }
    }

    private var submitTitle: String {
        switch effectiveEvent {
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request changes"
        case .comment:
            return session.pendingReview.isSubmitting ? "Submitting..." : "Submit review"
        }
    }
}
