import SwiftUI

/// Hosts the shared markdown editor for the `AGENTS.md` draft. The draft and undo
/// controller live on the model so reconfiguration cannot drop editor state.
struct AgentsInstructionsEditor: View {
    private static let visibleLineCount = 16

    let model: GlobalInstructionsEditorModel

    var body: some View {
        // Keyed on the generation so async disk loads invalidate this view;
        // without an observed read SwiftUI skips body (the model pointer never
        // changes) and `updateNSView` would never re-run `configure` after the
        // load. A reload replaces the whole document, so rebuilding the editor
        // view is the intended effect.
        AppMarkdownEditor(
            draft: model.draft,
            placeholder: "Write shared agent instructions in markdown...",
            // `sizeThatFits` is unreliable inside the settings `ScrollView` (an
            // unbounded vertical proposal balloons the editor), so this mode
            // applies BlockInputKit's reported height through an explicit frame.
            sizing: .fixedLineCount(Self.visibleLineCount),
            // Literal `@/path` include lines render as file chips; the text
            // itself stays untouched so Claude's `@` include syntax survives.
            rawFileMentionChips: true,
            undoController: model.undoController,
            onDocumentChange: model.noteDocumentChanged
        )
        .id(model.contentGeneration)
    }
}
