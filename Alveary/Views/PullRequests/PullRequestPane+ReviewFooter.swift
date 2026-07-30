import SwiftUI

/// The pending-batch review footer: shows the queued inline-comment count and an
/// expandable summary composer for submitting the whole review in one call.
struct PullRequestPaneReviewFooter: View {
    let viewModel: PullRequestsViewModel
    let session: PullRequestPaneSession

    @State private var isExpanded: Bool
    @State private var selectedEvent = PullRequestReviewEvent.comment
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

            if isExpanded {
                summaryComposer
            }

            actionRow
        }
        .padding(ContextualPaneLayout.contentInsets())
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }

    /// GitHub rejects Approve and Request changes on your own pull request, so
    /// they only appear for other people's PRs; your own submit as a comment.
    private var allowsVerdictEvents: Bool {
        if session.summary.isAuthored {
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

    private var canSubmit: Bool {
        !session.pendingReview.isSubmitting
            && PullRequestsViewModel.canSubmitReview(event: effectiveEvent, draft: draftForValidation)
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

    private var actionRow: some View {
        HStack(spacing: 8) {
            let count = session.pendingReview.comments.count
            if count > 0 {
                Text("\(count) pending comment\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isExpanded {
                Button("Cancel", action: cancelComposer)
                    .secondaryActionButtonStyle()
                    .disabled(session.pendingReview.isSubmitting)

                Button(submitTitle) {
                    submitIfAllowed()
                }
                .primaryActionButtonStyle()
                .disabled(!canSubmit)
            } else {
                Button("Submit review...") {
                    overallDraft = PullRequestCommentDraftBox(
                        markdown: viewModel.activePaneSession?.pendingReview.overallComment ?? ""
                    )
                    isExpanded = true
                }
                .primaryActionButtonStyle()
            }
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
