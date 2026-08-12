import SwiftUI

/// The modal editor for the shared `AGENTS.md` file, opened from the Agents tab's
/// `Edit` row.
///
/// Internal rather than file-private so snapshots can host it; `AgentsInstructionsSection`
/// is the only production presenter. Unlike `SettingsPromptEditorSheet` the draft lives on
/// the model, not the presenting row, so `Cancel` deliberately keeps unsaved edits — the
/// row surfaces them as "Unsaved changes" and `Revert` is the way to discard. Save
/// dismisses only once the write lands, leaving a failure readable over the user's text.
struct AgentsInstructionsEditorSheet: View {
    let model: GlobalInstructionsEditorModel
    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var confirmation: DestructiveConfirmationRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AGENTS.md")
                .font(.title3.weight(.semibold))

            AgentsInstructionsEditor(model: model, onSubmit: submit, onCancel: onCancel)
                .frame(maxHeight: .infinity)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Saving rewrites \(model.sharedPathDescription) in canonical markdown, so spacing may differ from the original file.")
                .font(.caption)
                .foregroundStyle(.secondary)

            actionRow
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 620)
        .destructiveConfirmation($confirmation)
    }
}

private extension AgentsInstructionsEditorSheet {
    var actionRow: some View {
        HStack {
            Button("Revert", action: requestRevert)
                .secondaryActionButtonStyle()
                .disabled(!model.isDirty)

            Spacer()

            Button("Cancel", action: onCancel)
                .secondaryActionButtonStyle()

            Button("Save", action: save)
                .primaryActionButtonStyle()
                .disabled(!model.isDirty)
        }
    }

    /// Cmd+Return routes here rather than to `save` so the shortcut honours the
    /// same enablement guard as the disabled Save button.
    func submit() {
        guard model.isDirty else {
            return
        }
        save()
    }

    func save() {
        Task {
            if await model.save() {
                onSaved()
            }
        }
    }

    func requestRevert() {
        confirmation = DestructiveConfirmationRequest(
            title: "Revert changes?",
            message: "This discards unsaved changes and reloads \(model.sharedPathDescription) from disk.",
            confirmTitle: "Revert",
            confirm: {
                Task {
                    await model.revert()
                }
            }
        )
    }
}
