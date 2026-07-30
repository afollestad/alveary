import AppKit
import BlockInputKit
import SwiftUI

/// One comment-composing session: the BlockInputKit document store plus the cheap
/// emptiness flag hosts use for Save enablement. The store owns the live text —
/// markdown is serialized only when a host saves, never per keystroke.
@MainActor
@Observable
final class PullRequestCommentDraftBox {
    @ObservationIgnored let store: BlockInputMemoryDocumentStore
    private(set) var isEffectivelyEmpty: Bool

    init(markdown: String) {
        store = BlockInputMemoryDocumentStore(document: BlockInputDocument(markdown: markdown))
        isEffectivelyEmpty = store.document.isEffectivelyEmpty
    }

    var markdown: String {
        store.document.markdown
    }

    /// Guarded so per-keystroke document changes publish only on transitions.
    func noteDocumentChanged(_ document: BlockInputDocument) {
        let empty = document.isEffectivelyEmpty
        if isEffectivelyEmpty != empty {
            isEffectivelyEmpty = empty
        }
    }

    /// Programmatic replacement (tests, restored drafts); the editor rebuilds from
    /// the store, so this must not run mid-typing.
    func replaceText(_ markdown: String) {
        store.replaceDocument(BlockInputDocument(markdown: markdown))
        noteDocumentChanged(store.document)
    }
}

/// BlockInputKit-backed markdown editor shared by the inline diff composer and the
/// review footer. Composer-only features (completions, slash commands, drops) stay
/// off; the height grows with content up to a cap, then scrolls internally.
struct PullRequestCommentEditor: View {
    let draft: PullRequestCommentDraftBox
    let placeholder: String
    var isFocused: Binding<Bool>?
    /// Fired on Cmd+Return inside the editor. Hosts run their primary save/submit
    /// action here, including its enablement guard — the shortcut must never
    /// bypass a disabled Save/Submit button.
    var onSubmit: (() -> Void)?
    /// Fired on Escape inside the editor; hosts run the same action as their
    /// Cancel button.
    var onCancel: (() -> Void)?

    // No height state: `BlockInputEditor.sizeThatFits` reports the clamped
    // preferred height synchronously during layout, so mounting and line
    // growth resize in the same frame as the change. A host-side
    // `onPreferredHeightChange` + `.frame(height:)` round trip lags a frame
    // behind the AppKit editor and reads as a glitchy vertical jump.
    var body: some View {
        editor
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var editor: some View {
        if let isFocused {
            BlockInputEditor(configuration: configuration, isFocused: isFocused)
        } else {
            BlockInputEditor(configuration: configuration)
        }
    }

    private var configuration: BlockInputConfiguration {
        BlockInputConfiguration(
            documentStore: draft.store,
            allowsBlockReordering: false,
            allowsDrops: false,
            placeholder: placeholder,
            style: Self.style,
            heightSizing: BlockInputEditorHeightSizing(
                defaultVisibleLineCount: 3,
                maximumVisibleLineCount: 10
            ),
            keyboardShortcuts: keyboardShortcuts,
            onDocumentChange: { [weak draft] document in
                Task { @MainActor in
                    draft?.noteDocumentChanged(document)
                }
            }
        )
    }

    /// Cmd+Return submits and Escape cancels when the host provides the action;
    /// plain Return stays a newline because comments are multi-line, unlike the
    /// chat composer.
    private var keyboardShortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] {
        var shortcuts: [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] = [:]
        if let onSubmit {
            shortcuts[BlockInputKeyboardShortcut(key: .return, modifiers: .command)] = { _ in
                onSubmit()
                return .handled
            }
        }
        if let onCancel {
            shortcuts[BlockInputKeyboardShortcut(key: .escape)] = { _ in
                onCancel()
                return .handled
            }
        }
        return shortcuts
    }

    /// Local chrome matching the app's input styling; deliberately not
    /// `BlockInputComposerStyle`, which reaches into composer layout constants.
    private static var style: BlockInputStyle {
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
