import SwiftUI

/// Inline editor for timeline comment edits and thread replies, mirroring the
/// Changes tab's in-thread editor controls: error banner, shared BlockInputKit
/// editor, and Cancel / save buttons.
struct PullRequestActivityCommentEditor: View {
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel
    var saveTitle = "Update comment"
    /// Travels with `saveTitle`; a reply is the one caller that is not editing
    /// an existing comment, so it swaps in the reply glyph.
    var saveIcon = ActionIcon.octicon("CommentOcticon16")
    var placeholder = "Edit this comment"
    /// Forwarded to the editor; the PR description opens taller than a comment.
    var minimumVisibleLineCount = 2

    @State private var isEditorFocused = false

    private var isUploading: Bool {
        viewModel.isUploadingAttachments(to: .composer)
    }

    /// Saving while an upload is in flight would post the comment without the
    /// attachment's link, so the upload gates Save.
    private var canSave: Bool {
        !(viewModel.composerDraft?.isEffectivelyEmpty ?? true) && !isUploading
    }

    /// Shared by the Update button and the editor's Cmd+Return shortcut so the
    /// shortcut cannot bypass the button's enablement.
    private func saveIfAllowed() {
        guard canSave else {
            return
        }
        viewModel.saveComposerComment()
    }

    private func attach(_ files: [URL]) {
        guard let draft = viewModel.composerDraft else {
            return
        }
        viewModel.attachFiles(files, to: .composer, draft: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = session.composerError {
                InlineBanner(message: errorMessage, severity: .error, autoDismissAfter: nil, onDismiss: nil)
            }

            if let draft = viewModel.composerDraft {
                PullRequestCommentEditor(
                    draft: draft,
                    placeholder: placeholder,
                    minimumVisibleLineCount: minimumVisibleLineCount,
                    isFocused: $isEditorFocused,
                    onSubmit: saveIfAllowed,
                    onCancel: { viewModel.cancelCommentComposer() }
                )
                .onChange(of: session.composerFocusToken, initial: true) { _, token in
                    guard token != nil else {
                        return
                    }
                    isEditorFocused = true
                    viewModel.consumeComposerFocusToken()
                }
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                if viewModel.supportsAttachmentUploads {
                    PullRequestCommentAttachButton(isUploading: isUploading, onPick: attach)
                }

                Button {
                    viewModel.cancelCommentComposer()
                } label: {
                    ActionButtonLabel(title: "Cancel", icon: .system("xmark"))
                }
                .secondaryActionButtonStyle()
                .controlSize(.small)

                Button {
                    viewModel.saveComposerComment()
                } label: {
                    ActionButtonLabel(title: saveTitle, icon: saveIcon)
                }
                .primaryActionButtonStyle()
                .controlSize(.small)
                .disabled(!canSave)
            }
        }
        .pullRequestAttachmentDropTarget(
            isEnabled: viewModel.supportsAttachmentUploads && !isUploading,
            onDrop: attach
        )
    }
}
