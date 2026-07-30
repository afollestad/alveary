import SwiftUI

/// Editor, error banner, and Cancel/Save controls shared by the standalone
/// composer row (new comments, replies) and the inline in-thread editor.
struct DiffCommentEditorControls: View {
    let anchor: DiffCommentAnchor
    let interaction: DiffCommentInteraction

    @State private var isEditorFocused = false

    private var composerMode: DiffCommentComposerMode {
        interaction.composerMode(anchor)
    }

    /// Saving mid-upload would post the comment without the attachment's link.
    private var canSave: Bool {
        !(interaction.draft?.isEffectivelyEmpty ?? true) && !interaction.isUploadingAttachments
    }

    /// Shared by the Save button and the editor's Cmd+Return shortcut so the
    /// shortcut cannot bypass the button's enablement.
    private func saveIfAllowed() {
        guard canSave else {
            return
        }
        interaction.onSaveDraft()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = interaction.composerErrorMessage {
                InlineBanner(message: errorMessage, severity: .error, autoDismissAfter: nil, onDismiss: nil)
            }

            if let draft = interaction.draft {
                PullRequestCommentEditor(
                    draft: draft,
                    placeholder: composerMode.isEditing ? "Edit this comment" : "Leave a comment",
                    isFocused: $isEditorFocused,
                    onSubmit: saveIfAllowed,
                    onCancel: interaction.onCancelComposer
                )
                .onChange(of: interaction.composerFocusToken, initial: true) { _, token in
                    guard token != nil else {
                        return
                    }
                    isEditorFocused = true
                    interaction.onComposerFocusConsumed()
                }
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                if let onAttachFiles = interaction.onAttachFiles {
                    PullRequestCommentAttachButton(
                        isUploading: interaction.isUploadingAttachments,
                        onPick: onAttachFiles
                    )
                }

                Button("Cancel", action: interaction.onCancelComposer)
                    .secondaryActionButtonStyle()
                    .controlSize(.small)

                Button(composerMode.saveTitle) {
                    interaction.onSaveDraft()
                }
                .primaryActionButtonStyle()
                .controlSize(.small)
                .disabled(!canSave)
            }
        }
        .pullRequestAttachmentDropTarget(
            isEnabled: interaction.onAttachFiles != nil && !interaction.isUploadingAttachments,
            onDrop: { interaction.onAttachFiles?($0) }
        )
    }
}

struct DiffCommentComposerRow: View {
    let anchor: DiffCommentAnchor
    let interaction: DiffCommentInteraction

    var body: some View {
        DiffCommentEditorControls(anchor: anchor, interaction: interaction)
            .modifier(DiffCommentCardChrome())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("New comment on line \(anchor.line) of \(anchor.path)")
    }
}
