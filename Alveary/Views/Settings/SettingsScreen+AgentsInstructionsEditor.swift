import SwiftUI

/// Hosts the shared markdown editor for the `AGENTS.md` draft. The draft and undo
/// controller live on the model so reconfiguration cannot drop editor state.
struct AgentsInstructionsEditor: View {
    let model: GlobalInstructionsEditorModel
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        // Keyed on the generation so a disk reload invalidates this view; without
        // an observed read SwiftUI skips body (the model pointer never changes)
        // and `updateNSView` would never re-run `configure` after Revert or the
        // async first load. A reload replaces the whole document, so rebuilding
        // the editor view is the intended effect.
        AppMarkdownEditor(
            draft: model.draft,
            placeholder: "Write shared agent instructions in markdown...",
            sizing: .fillsAvailableHeight,
            // Literal `@/path` include lines render as file chips; the text
            // itself stays untouched so Claude's `@` include syntax survives.
            rawFileMentionChips: true,
            undoController: model.undoController,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onDocumentChange: model.noteDocumentChanged
        )
        .id(model.contentGeneration)
    }
}
