import SwiftUI

struct PullRequestPaneFiles: View {
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel

    // The delete-comment confirmation dialog lives on `PullRequestPane`, shared
    // with the Overview timeline, so arming a deletion on either tab presents it.
    var body: some View {
        VStack(spacing: 0) {
            diffStateContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // failures here; open composers and inline editors — including the
        // Overview timeline's — show the same error inline instead.
        if let error = session.composerError,
           session.composerAnchor == nil,
           session.composerRemoteCommentID == nil,
           session.composerIssueCommentID == nil,
           session.composerReviewID == nil,
           session.composerReplyToCommentID == nil {
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
                contentTopInset: ContextualPaneLayout.contentInsets().top,
                // The pane inset folds into the scroll content instead of
                // wrapping the preview, so the scroll bar sits flush with the
                // pane edge like the Overview tab's while the rows keep the tab
                // row's and pane title's horizontal alignment.
                horizontalContentInset: ContextualPaneLayout.horizontalInset
                    + DiffViewerPaneMetrics.diffPreviewHorizontalInset
            )

            let remaining = PullRequestDiffFilePaging.remainingFileCount(
                total: files.count,
                renderedFileCount: session.renderedDiffFileCount
            )
            if remaining > 0 {
                showMoreFooter(remaining: remaining)
            }
        }
    }

    /// Review threads keyed by anchor. The viewer's own unsubmitted comments are
    /// ordinary threads here — GitHub keeps them in `reviewThreads` badged
    /// `PENDING`, so nothing local has to be merged in.
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
                    comments: thread.comments.map(commentRow(for:)),
                    isResolved: thread.isResolved,
                    isOutdated: thread.isOutdated,
                    threadID: thread.nodeID,
                    isPending: thread.isPending
                )
            }
        }
        // Edits render inline inside their thread; only new comments and replies
        // get the standalone composer row below it.
        let isInlineEdit = session.composerRemoteCommentID != nil
            || session.composerPendingCommentNodeID != nil
        annotations.composerAnchor = isInlineEdit ? nil : session.composerAnchor
        return annotations
    }

    /// A pending comment is addressed by node id, so its menu waits on that
    /// rather than the REST id a submitted comment needs.
    private func commentRow(for comment: PullRequestComment) -> DiffLineComment {
        let hasActionableID = comment.isPending ? comment.nodeID != nil : comment.databaseId != nil
        return DiffLineComment(
            author: comment.authorLogin,
            bodyMarkdown: PullRequestMarkdown.sanitized(comment.bodyMarkdown),
            isPending: comment.isPending,
            remoteID: comment.databaseId,
            nodeID: comment.nodeID,
            canEdit: comment.viewerCanUpdate && hasActionableID,
            canDelete: comment.viewerCanDelete && hasActionableID,
            reactions: comment.reactions.map(\.asCommentReaction),
            avatarURL: comment.authorAvatarURL,
            isBot: comment.isBot,
            relativeAge: comment.createdAt.map {
                compactRelativeAge(from: $0, relativeTo: viewModel.referenceDate)
            },
            absoluteTimestamp: comment.createdAt.map {
                PullRequestTimestampFormatting.absoluteString(for: $0)
            }
        )
    }

    private var commentInteraction: DiffCommentInteraction {
        DiffCommentInteraction(
            draft: viewModel.composerDraft,
            composerMode: { _ in
                if viewModel.activePaneSession?.composerRemoteCommentID != nil {
                    return .editRemote
                }
                if viewModel.activePaneSession?.composerPendingCommentNodeID != nil {
                    return .editPending
                }
                if viewModel.activePaneSession?.composerReplyToCommentID != nil {
                    return .reply
                }
                return .newComment
            },
            composerErrorMessage: session.composerError,
            composerFocusToken: session.composerFocusToken,
            editingRemoteCommentID: session.composerRemoteCommentID,
            editingPendingCommentNodeID: session.composerPendingCommentNodeID,
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
            onDeleteRemoteComment: { _, comment in
                viewModel.requestDeleteRemoteComment(comment: comment)
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
            onDeletePending: { comment in
                guard let nodeID = comment.nodeID else {
                    return
                }
                viewModel.deletePendingComment(nodeID: nodeID)
            },
            onAttachFiles: viewModel.supportsAttachmentUploads ? { files in
                guard let draft = viewModel.composerDraft else {
                    return
                }
                viewModel.attachFiles(files, to: .composer, draft: draft)
            } : nil,
            isUploadingAttachments: viewModel.isUploadingAttachments(to: .composer)
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
        .contextualPaneFooterChrome()
    }
}
