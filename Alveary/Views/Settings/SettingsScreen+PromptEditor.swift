import SwiftUI

struct SettingsPromptEditorRow: View {
    let title: String
    let helpText: String
    let defaultPrompt: String
    let placeholder: String
    let showsDivider: Bool

    @Binding var prompt: String

    @State private var isEditorPresented = false
    /// Row-lived so the sheet never rebuilds its document store mid-session; the
    /// Edit action seeds it, and nothing reaches `prompt` until Save.
    @State private var draft = AppMarkdownDraft(markdown: "")

    init(
        _ title: String,
        helpText: String,
        prompt: Binding<String>,
        defaultPrompt: String,
        placeholder: String,
        showsDivider: Bool = true
    ) {
        self.title = title
        self.helpText = helpText
        _prompt = prompt
        self.defaultPrompt = defaultPrompt
        self.placeholder = placeholder
        self.showsDivider = showsDivider
    }

    var body: some View {
        SettingsFormRow(showsDivider: showsDivider) {
            SettingsResponsiveControlRow(title, helpText: helpText, horizontalControlSizing: .intrinsicInline) {
                Button("Edit") {
                    draft.referenceMarkdown = defaultPrompt
                    draft.resetContent(to: prompt)
                    isEditorPresented = true
                }
                .secondaryActionButtonStyle()
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            SettingsPromptEditorSheet(
                title: title,
                draft: draft,
                defaultPrompt: defaultPrompt,
                placeholder: placeholder,
                onCancel: {
                    isEditorPresented = false
                },
                onSave: {
                    prompt = draft.markdown
                    isEditorPresented = false
                }
            )
        }
    }
}

/// Internal rather than file-private so snapshots can host it directly; the row's
/// `.sheet` is the only production presenter.
struct SettingsPromptEditorSheet: View {
    let title: String
    let draft: AppMarkdownDraft
    let defaultPrompt: String
    let placeholder: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            AppMarkdownEditor(
                draft: draft,
                placeholder: placeholder,
                sizing: .fillsAvailableHeight,
                onSubmit: onSave,
                onCancel: onCancel
            )
            .frame(maxHeight: .infinity)

            HStack {
                Button("Reset") {
                    draft.resetContent(to: defaultPrompt)
                }
                .secondaryActionButtonStyle()
                .disabled(draft.matchesReference)

                Spacer()

                Button("Cancel", action: onCancel)
                    .secondaryActionButtonStyle()

                Button("Save", action: onSave)
                    .primaryActionButtonStyle()
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 620)
    }
}
