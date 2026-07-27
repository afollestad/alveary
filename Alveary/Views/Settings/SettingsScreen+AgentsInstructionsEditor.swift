import AppKit
import BlockInputKit
import SwiftUI

/// Hosts the BlockInputKit editor for the shared `AGENTS.md` draft. The document
/// store and undo controller live on the model so reconfiguration cannot drop
/// editor state; composer-only features (completions, slash commands, drops)
/// stay off.
struct AgentsInstructionsEditor: View {
    /// Fallback until BlockInputKit reports the fixed viewport height. Matches
    /// the measured 16-line height so the first layout pass — including
    /// single-pass snapshot renders that never process the height callback —
    /// already reserves the right slot instead of letting the AppKit view
    /// spill over its neighbors.
    private static let fallbackHeight: CGFloat = 480

    let model: GlobalInstructionsEditorModel

    @State private var editorHeight: CGFloat = AgentsInstructionsEditor.fallbackHeight

    var body: some View {
        // Keyed on the generation so async disk loads invalidate this view;
        // without an observed read SwiftUI skips body (the model pointer never
        // changes) and `updateNSView` would never re-run `configure` after the
        // load. A reload replaces the whole document, so rebuilding the editor
        // view is the intended effect.
        BlockInputEditor(configuration: configuration)
            .id(model.contentGeneration)
            // `sizeThatFits` is unreliable inside the settings `ScrollView`
            // (an unbounded vertical proposal balloons the editor), so apply
            // the preferred height reported by BlockInputKit ourselves, like
            // the composer host does. Default and maximum line counts match,
            // so the reported height is constant and adding or removing lines
            // never resizes the editor; overflow scrolls internally.
            .frame(height: editorHeight)
            .frame(maxWidth: .infinity)
    }
}

private extension AgentsInstructionsEditor {
    var configuration: BlockInputConfiguration {
        BlockInputConfiguration(
            documentStore: model.documentStore,
            allowsBlockReordering: false,
            allowsDrops: false,
            placeholder: "Write shared agent instructions in markdown...",
            // Literal `@/path` include lines render as file chips; the text
            // itself stays untouched so Claude's `@` include syntax survives.
            rawFileMentionChips: true,
            style: Self.style,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 16,
                maximumVisibleLineCount: 16,
                onPreferredHeightChange: { height in
                    if editorHeight != height {
                        editorHeight = height
                    }
                }
            ),
            undoController: model.undoController,
            onDocumentChange: { [weak model] _ in
                Task { @MainActor in
                    model?.noteDocumentChanged()
                }
            }
        )
    }

    /// Local editor chrome matching the app's input styling; deliberately not
    /// `BlockInputComposerStyle`, which reaches into composer layout constants.
    static var style: BlockInputStyle {
        var style = BlockInputStyle.default
        style.editorSurface = BlockInputEditorSurfaceStyle(
            editorBackgroundColor: nil,
            scrollBackgroundColor: nil,
            collectionBackgroundColor: nil,
            chrome: BlockInputEditorChromeStyle(
                fillColor: NSColor.textBackgroundColor.withAlphaComponent(0.55),
                strokeColor: NSColor.separatorColor,
                borderWidth: 1,
                cornerRadius: 8,
                clipsContentToShape: true
            )
        )
        return style
    }
}
