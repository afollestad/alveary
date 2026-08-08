import SwiftUI

/// The pending-batch review footer: shows the queued inline-comment count and an
/// expandable summary composer for submitting the whole review in one call.
struct PullRequestPaneReviewFooter: View, Equatable {
    let viewModel: PullRequestsViewModel
    let session: PullRequestPaneSession
    /// Which pull request this footer submits for, so it can resolve a pending review proposal
    /// without asking which pane happens to be active — the same reason `PullRequestPaneFiles`
    /// carries one.
    let target: PullRequestPaneTarget

    /// `initiallyExpanded` and the persisted review-action kind only seed `@State`, so
    /// neither is part of the rendered inputs.
    nonisolated static func == (lhs: PullRequestPaneReviewFooter, rhs: PullRequestPaneReviewFooter) -> Bool {
        lhs.session == rhs.session && lhs.viewModel === rhs.viewModel && lhs.target == rhs.target
    }

    @State private var isExpanded: Bool
    @State private var selectedEvent = PullRequestReviewEvent.comment
    /// Nil takes the default action; a stale pick falls back the same way.
    @State private var selectedStateKind: PullRequestStateAction.Kind?
    /// Seeded from settings at init rather than read in `body`: this view is a
    /// memoization boundary whose `==` excludes settings, so a `body` read would not
    /// re-render when the stored kind changed anyway.
    @State private var selectedReviewKind: PullRequestReviewFooterAction.Kind
    /// BlockInputKit store for the overall comment; created when the composer
    /// expands, serialized back into the pending draft on collapse or submit.
    @State private var overallDraft: PullRequestCommentDraftBox?

    init(
        viewModel: PullRequestsViewModel,
        session: PullRequestPaneSession,
        target: PullRequestPaneTarget,
        initiallyExpanded: Bool = false
    ) {
        self.viewModel = viewModel
        self.session = session
        self.target = target
        _isExpanded = State(initialValue: initiallyExpanded)
        _selectedReviewKind = State(initialValue: viewModel.selectedReviewFooterActionKind)
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

            if let error = session.agenticReviewError {
                InlineBanner(
                    message: error,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: viewModel.clearAgenticReviewError
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

    /// Inline comments live on GitHub, so the count starts from the detail — plus a pending
    /// proposal's staged comments, which the same Submit publishes because it routes through the
    /// coordinator. `submitReview`'s own guard reads the same sum, so this button cannot offer a
    /// submit the view model then silently refuses.
    private var pendingCommentCount: Int {
        viewModel.submittableCommentCount(for: target, session: session)
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

    /// Names what Submit would publish. "Pending" is GitHub's own word for the viewer's draft, and
    /// a staged comment wears the "Proposed" pill instead — so once the count spans both, it can
    /// borrow neither pill's name and says plainly what the number is.
    private var commentCountNote: String? {
        let count = pendingCommentCount
        guard count > 0 else {
            return nil
        }
        let plural = count == 1 ? "" : "s"
        guard viewModel.pendingReviewProposal(for: target)?.comments.isEmpty == false else {
            return "\(count) pending comment\(plural)"
        }
        return "\(count) comment\(plural) in this review"
    }

    /// The comment count and any reason the state action is dead. Both sit above
    /// the buttons: the collapsed row splits its width evenly between the two
    /// actions, leaving no room for a leading label.
    @ViewBuilder
    private var footerNotes: some View {
        if let note = commentCountNote {
            Text(note)
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
    /// available action — which is what retires "Ready for review" the moment
    /// the pull request leaves draft. Same guard as `effectiveEvent`.
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
                reviewActionButton(expandsHorizontally: true)
                    .frame(minWidth: ContextualPaneLayout.minimumHorizontalActionWidth, maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                reviewActionButton(expandsHorizontally: false)
            }
        }
    }

    private var composingActionRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if viewModel.supportsAttachmentUploads {
                PullRequestCommentAttachButton(isUploading: isUploading, onPick: attach)
            }

            Button(action: cancelComposer) {
                ActionButtonLabel(title: "Cancel", icon: .system("xmark"))
            }
            .secondaryActionButtonStyle()
            .disabled(session.pendingReview.isSubmitting)

            Button {
                submitIfAllowed()
            } label: {
                ActionButtonLabel(title: submitTitle, icon: submitIcon)
            }
            .primaryActionButtonStyle()
            .disabled(!canSubmit)
        }
    }

    /// Both options apply to every pull request, so this is always a split button. The caret
    /// selects only — the row's one accent voice stays `.primary` either way.
    private func reviewActionButton(expandsHorizontally: Bool) -> some View {
        let action = PullRequestReviewFooterAction.action(for: effectiveReviewKind)
        return SplitActionButton(
            title: action.title,
            icon: action.icon,
            emphasis: .primary,
            expandsHorizontally: expandsHorizontally,
            selectedOption: action.kind,
            options: PullRequestReviewFooterAction.all.map(\.kind),
            optionTitle: { PullRequestReviewFooterAction.action(for: $0).title },
            action: { runReviewAction(action.kind) },
            selectOption: { kind in
                selectedReviewKind = kind
                viewModel.selectReviewFooterAction(kind)
            }
        )
        .disabled(session.isStartingAgenticReview)
        .help(action.title)
    }

    /// A written review outranks the stored pick. With staged comments waiting, the default
    /// action is finishing that review — starting a second agentic one would be the wrong door,
    /// and its proposal would supersede the comments on screen. The caret still reaches Agentic
    /// review, so this changes the default rather than removing the option; it mirrors
    /// `effectiveEvent` and `effectiveStateAction`, which retire stale picks the same way.
    private var effectiveReviewKind: PullRequestReviewFooterAction.Kind {
        guard viewModel.pendingReviewProposal(for: target)?.comments.isEmpty == false else {
            return selectedReviewKind
        }
        return .submitReview
    }

    private func runReviewAction(_ kind: PullRequestReviewFooterAction.Kind) {
        switch kind {
        case .submitReview:
            overallDraft = PullRequestCommentDraftBox(
                markdown: viewModel.activePaneSession?.pendingReview.overallComment ?? ""
            )
            isExpanded = true
        case .agenticReview:
            viewModel.startAgenticReview()
        }
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
                icon: action.icon,
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
        let button = Button {
            run(action)
        } label: {
            ActionButtonLabel(title: action.title, icon: action.icon)
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

    /// Tracks `submitTitle` arm for arm — the three verdicts swap inside one
    /// button, so title and glyph have to be resolved from the same switch.
    private var submitIcon: ActionIcon {
        switch effectiveEvent {
        case .approve:
            return .octicon(.checkCircle16)
        case .requestChanges:
            return .octicon(.alert16)
        case .comment:
            return .octicon(.codeReview16)
        }
    }
}
