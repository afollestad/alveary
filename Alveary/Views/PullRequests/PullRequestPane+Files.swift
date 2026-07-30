import SwiftUI

struct PullRequestPaneFiles: View {
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel

    var body: some View {
        VStack(spacing: 0) {
            diffStateContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Delete comment?",
            isPresented: Binding(
                get: { session.pendingRemoteCommentDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelRemoteCommentDeletion()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.confirmRemoteCommentDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelRemoteCommentDeletion()
            }
        } message: {
            Text("The comment is permanently deleted from the pull request on GitHub.")
        }
    }

    @ViewBuilder
    private var diffStateContent: some View {
        switch session.diffState {
        case .loading:
            StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading diff")
        case .tooLarge:
            EmptyStateView(
                icon: "doc.zipper",
                heading: "Diff too large",
                subtext: "This pull request's diff exceeds the 5 MB preview limit. View it on GitHub instead.",
                actions: []
            )
        case .failed(let message):
            EmptyStateView(
                icon: "exclamationmark.triangle",
                heading: "Diff unavailable",
                subtext: message,
                actions: []
            )
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let files = session.diffFiles ?? []
        // Remote comment actions (delete, and edits with the composer closed) report
        // failures here; the open composer shows the same error inline instead.
        if let error = session.composerError, session.composerAnchor == nil {
            InlineBanner(
                message: error,
                severity: .error,
                autoDismissAfter: nil,
                onDismiss: { viewModel.clearCommentActionError() }
            )
            .contextualPaneHorizontalInsets()
            .padding(.top, 8)
        }
        if files.isEmpty {
            EmptyStateView(
                icon: "doc.text",
                heading: "No changes",
                subtext: "This pull request has no file changes.",
                actions: []
            )
        } else {
            let rendered = PullRequestDiffFilePaging.renderedFiles(
                files,
                renderedFileCount: session.renderedDiffFileCount
            )
            FlattenedDiffPreview(
                files: rendered,
                showsFileHeaders: true,
                allowsFileCollapse: true,
                collapsedFileIDs: session.collapsedDiffFileIDs,
                onToggleFileCollapse: { fileID in
                    viewModel.toggleDiffFileCollapse(fileID)
                },
                commentAnnotations: commentAnnotations,
                commentInteraction: commentInteraction,
                // Match Overview's and Activity's top content inset.
                contentTopInset: ContextualPaneLayout.contentInsets().top
            )
            // Match the tab row's and pane title's horizontal insets.
            .contextualPaneHorizontalInsets()

            let remaining = PullRequestDiffFilePaging.remainingFileCount(
                total: files.count,
                renderedFileCount: session.renderedDiffFileCount
            )
            if remaining > 0 {
                showMoreFooter(remaining: remaining)
            }
        }
    }

    /// Existing review threads plus the local pending batch, keyed by anchor.
    private var commentAnnotations: DiffCommentAnnotations {
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = true
        if let detail = session.detail {
            for thread in detail.reviewThreads where !thread.isOutdated {
                guard let line = thread.line else {
                    continue
                }
                let anchor = DiffCommentAnchor(
                    path: thread.path,
                    side: thread.side == .left ? .left : .right,
                    line: line
                )
                annotations.threads[anchor] = DiffLineCommentThread(
                    comments: thread.comments.map { comment in
                        DiffLineComment(
                            author: comment.authorLogin,
                            bodyMarkdown: PullRequestMarkdown.sanitized(comment.bodyMarkdown),
                            isPending: false,
                            remoteID: comment.databaseId,
                            nodeID: comment.nodeID,
                            canEdit: comment.viewerCanUpdate && comment.databaseId != nil,
                            canDelete: comment.viewerCanDelete && comment.databaseId != nil,
                            reactions: comment.reactions.map(\.asCommentReaction),
                            avatarURL: comment.authorAvatarURL,
                            isBot: comment.isBot
                        )
                    },
                    isResolved: thread.isResolved,
                    isOutdated: thread.isOutdated,
                    threadID: thread.nodeID
                )
            }
        }
        for pending in session.pendingReview.comments {
            var thread = annotations.threads[pending.anchor] ?? DiffLineCommentThread(comments: [])
            // Pending comments belong to the signed-in viewer; the detail query's
            // `viewer` field supplies the same identity GitHub would show.
            thread.comments.append(DiffLineComment(
                author: session.detail?.viewerLogin ?? "You",
                bodyMarkdown: pending.body,
                isPending: true,
                avatarURL: session.detail?.viewerAvatarURL
            ))
            annotations.threads[pending.anchor] = thread
        }
        // Edits render inline inside their thread; only new comments and replies
        // get the standalone composer row below it.
        let isInlineEdit = session.composerRemoteCommentID != nil || editingPendingAnchor != nil
        annotations.composerAnchor = isInlineEdit ? nil : session.composerAnchor
        return annotations
    }

    /// The anchor whose pending-batch comment the composer is editing, if any —
    /// an open composer over an existing pending comment is an edit, not a new
    /// comment, so it renders inline.
    private var editingPendingAnchor: DiffCommentAnchor? {
        guard let anchor = session.composerAnchor,
              session.composerRemoteCommentID == nil,
              session.composerReplyToCommentID == nil,
              session.pendingReview.comments.contains(where: { $0.anchor == anchor }) else {
            return nil
        }
        return anchor
    }

    private var commentInteraction: DiffCommentInteraction {
        DiffCommentInteraction(
            draft: viewModel.composerDraft,
            composerMode: { anchor in
                if viewModel.activePaneSession?.composerRemoteCommentID != nil {
                    return .editRemote
                }
                if viewModel.activePaneSession?.composerReplyToCommentID != nil {
                    return .reply
                }
                let hasPending = viewModel.activePaneSession?.pendingReview.comments
                    .contains { $0.anchor == anchor } ?? false
                return hasPending ? .editPending : .newComment
            },
            composerErrorMessage: session.composerError,
            composerFocusToken: session.composerFocusToken,
            editingRemoteCommentID: session.composerRemoteCommentID,
            editingPendingAnchor: editingPendingAnchor,
            reactionOptions: PullRequestReactionContent.pickerOptions,
            avatarLoader: viewModel.avatarLoader,
            onComposerFocusConsumed: {
                viewModel.consumeComposerFocusToken()
            },
            onAddComment: { anchor in
                viewModel.openCommentComposer(at: anchor)
            },
            onEditRemoteComment: { anchor, comment in
                viewModel.openRemoteCommentEditor(at: anchor, comment: comment)
            },
            onDeleteRemoteComment: { anchor, comment in
                viewModel.requestDeleteRemoteComment(at: anchor, comment: comment)
            },
            onToggleReaction: { comment, content in
                viewModel.toggleReaction(
                    subjectID: comment.nodeID,
                    content: content,
                    viewerHasReacted: comment.reactions.first { $0.content == content }?.viewerHasReacted ?? false
                )
            },
            onReplyToThread: { anchor, thread in
                viewModel.openThreadReplyComposer(at: anchor, thread: thread)
            },
            onToggleThreadResolved: { _, thread in
                viewModel.setThreadResolved(threadID: thread.threadID, resolved: !thread.isResolved)
            },
            onSaveDraft: {
                viewModel.saveComposerComment()
            },
            onCancelComposer: {
                viewModel.cancelCommentComposer()
            },
            onDeletePending: { anchor in
                viewModel.removePendingComment(at: anchor)
            }
        )
    }

    private func showMoreFooter(remaining: Int) -> some View {
        HStack {
            Spacer(minLength: 0)

            Button {
                viewModel.showMoreDiffFiles()
            } label: {
                Text("Show \(min(PullRequestDiffFilePaging.fileCountStep, remaining)) more files (\(remaining) remaining)")
            }
            .secondaryActionButtonStyle()
            .controlSize(.small)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contextualPaneHorizontalInsets()
        .background(.bar)
        .overlay(alignment: .top) {
            AppSeparatorHairline(surface: .paneHeader)
        }
    }
}
