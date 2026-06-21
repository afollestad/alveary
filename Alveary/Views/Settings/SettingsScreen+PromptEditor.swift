import SwiftUI

struct SettingsPromptEditorRow: View {
    let title: String
    let helpText: String
    let defaultPrompt: String
    let placeholder: String
    let showsDivider: Bool

    @Binding var prompt: String

    @State private var isEditorPresented = false
    @State private var promptDraft = ""

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
                    promptDraft = prompt
                    isEditorPresented = true
                }
                .secondaryActionButtonStyle()
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            SettingsPromptEditorSheet(
                title: title,
                prompt: $promptDraft,
                defaultPrompt: defaultPrompt,
                placeholder: placeholder,
                onCancel: {
                    isEditorPresented = false
                },
                onSave: {
                    prompt = promptDraft
                    isEditorPresented = false
                }
            )
        }
    }
}

private struct SettingsPromptEditorSheet: View {
    let title: String
    @Binding var prompt: String
    let defaultPrompt: String
    let placeholder: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            AppTextEditor(
                text: $prompt,
                minHeight: 320,
                idealHeight: 360,
                maxHeight: 520,
                placeholder: placeholder,
                sizesToContent: false
            )

            HStack {
                Button("Reset") {
                    prompt = defaultPrompt
                }
                .secondaryActionButtonStyle()
                .disabled(prompt == defaultPrompt)

                Spacer()

                Button("Cancel", action: onCancel)
                    .secondaryActionButtonStyle()

                Button("Save", action: onSave)
                    .primaryActionButtonStyle()
            }
        }
        .padding(24)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480)
    }
}
