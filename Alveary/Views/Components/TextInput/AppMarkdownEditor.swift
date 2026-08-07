import AppKit
import BlockInputKit
import SwiftUI

/// One markdown-editing session: the BlockInputKit document store plus the cheap
/// flags hosts read for button enablement. The store owns the live text — markdown
/// is serialized only when a host commits, never per keystroke.
@MainActor
@Observable
final class AppMarkdownDraft {
    @ObservationIgnored let store: BlockInputMemoryDocumentStore
    private(set) var isEffectivelyEmpty: Bool
    /// True while the document matches `referenceMarkdown`, for hosts offering a
    /// Reset affordance. Always false when no reference was supplied.
    private(set) var matchesReference: Bool
    /// Bumped by `resetContent(to:)`. `AppMarkdownEditor` keys its editor on this,
    /// so a wholesale replacement rebuilds the AppKit view and lays the new
    /// document out from its top.
    private(set) var contentGeneration = 0

    /// Text a Reset action would restore. Compared against the serialized document
    /// on every change, so keep it to the sizes a settings prompt reaches.
    @ObservationIgnored var referenceMarkdown: String? {
        didSet {
            guard referenceMarkdown != oldValue else { return }
            refreshMatchesReference(store.document)
        }
    }

    init(markdown: String, referenceMarkdown: String? = nil) {
        let document = BlockInputDocument(markdown: markdown)
        store = BlockInputMemoryDocumentStore(document: document)
        isEffectivelyEmpty = document.isEffectivelyEmpty
        self.referenceMarkdown = referenceMarkdown
        matchesReference = referenceMarkdown == document.markdown
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
        refreshMatchesReference(document)
    }

    /// Programmatic replacement that keeps the mounted editor and its caret —
    /// splicing an attachment link into a comment being typed, for instance. The
    /// editor reloads from the store, so this must not run mid-keystroke.
    func replaceText(_ markdown: String) {
        store.replaceDocument(BlockInputDocument(markdown: markdown))
        noteDocumentChanged(store.document)
    }

    /// Swaps in a whole new document — Reset, a disk reload, a generated body.
    /// Unlike `replaceText`, this rebuilds the editor: a caret left over from the
    /// old document otherwise scrolls the new one under its top inset, clipping
    /// the first block against the editor chrome.
    func resetContent(to markdown: String) {
        replaceText(markdown)
        contentGeneration += 1
    }

    private func refreshMatchesReference(_ document: BlockInputDocument) {
        guard let referenceMarkdown else {
            if matchesReference {
                matchesReference = false
            }
            return
        }
        let matches = document.markdown == referenceMarkdown
        if matchesReference != matches {
            matchesReference = matches
        }
    }
}

/// How an `AppMarkdownEditor` claims vertical space.
enum AppMarkdownEditorSizing: Equatable {
    /// Takes whatever height the host proposes and scrolls internally past it.
    /// BlockInputKit reports no intrinsic height without `heightSizing`, so the
    /// host's own frame decides. Use this inside a fixed-size modal.
    case fillsAvailableHeight
    /// Grows with the content between the two line counts, then scrolls. Sizes
    /// through `BlockInputEditor.sizeThatFits` alone — an
    /// `onPreferredHeightChange` + `.frame(height:)` round trip applies the height
    /// a frame late and reads as a vertical jump.
    case growsToLineCount(minimum: Int, maximum: Int)
    /// A constant height for the given line count, applied through the host's own
    /// `.frame(height:)`. For `ScrollView` hosts, where an unbounded vertical
    /// proposal makes `sizeThatFits` balloon the editor.
    case fixedLineCount(Int)
}

/// The app's shared BlockInputKit markdown editor: PR comments, settings prompts,
/// commit messages, skill and scheduled-task instructions. Composer-only features
/// (completions, slash commands, drops, block reordering) stay off everywhere.
///
/// Hosts read `draft.markdown` at their own commit point. Writing serialized
/// markdown back into a `String` while the user types reconfigures the editor and
/// reloads its document mid-keystroke.
struct AppMarkdownEditor: View {
    let draft: AppMarkdownDraft
    let placeholder: String
    var sizing: AppMarkdownEditorSizing = .growsToLineCount(minimum: 2, maximum: 10)
    var isFocused: Binding<Bool>?
    var isEditable = true
    /// Renders literal `@/path` lines as file chips without touching the text, for
    /// hosts whose content carries Claude's `@` include syntax.
    var rawFileMentionChips = false
    /// Supply one when the host must keep undo history across reconfiguration.
    var undoController: BlockInputUndoController?
    /// Fired on Cmd+Return inside the editor. Hosts run their primary save/submit
    /// action here, including its enablement guard — the shortcut must never
    /// bypass a disabled Save/Submit button.
    var onSubmit: (() -> Void)?
    /// Fired on Escape inside the editor; hosts run the same action as their
    /// Cancel button.
    var onCancel: (() -> Void)?
    /// Fired on BlockInputKit's debounced document snapshot, for hosts tracking
    /// coarse state such as a dirty flag. Do not serialize markdown here.
    var onDocumentChange: (() -> Void)?

    @State private var fixedHeight: CGFloat?

    var body: some View {
        editor
            // Reading the generation here is what invalidates this view when a
            // host calls `resetContent(to:)` — the draft is a reference whose
            // pointer never changes, so nothing else would.
            .id(draft.contentGeneration)
            .modifier(HeightModifier(height: resolvedFixedHeight))
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

    /// `.fixedLineCount` reserves its measured height before BlockInputKit reports
    /// one, so a first layout pass — including single-pass snapshot renders that
    /// never process the height callback — does not let the AppKit view spill over
    /// its neighbors.
    private var resolvedFixedHeight: CGFloat? {
        guard case .fixedLineCount(let lineCount) = sizing else {
            return nil
        }
        return fixedHeight ?? CGFloat(lineCount) * Self.fallbackLineHeight
    }

    private static let fallbackLineHeight: CGFloat = 30

    private var configuration: BlockInputConfiguration {
        BlockInputConfiguration(
            documentStore: draft.store,
            allowsBlockReordering: false,
            allowsDrops: false,
            placeholder: placeholder,
            isEditable: isEditable,
            rawFileMentionChips: rawFileMentionChips,
            style: Self.style,
            heightSizing: heightSizing,
            undoController: undoController,
            keyboardShortcuts: keyboardShortcuts,
            onDocumentChange: { [weak draft] document in
                Task { @MainActor in
                    draft?.noteDocumentChanged(document)
                    onDocumentChange?()
                }
            }
        )
    }

    private var heightSizing: BlockInputEditorHeightSizing? {
        switch sizing {
        case .fillsAvailableHeight:
            return nil
        case .growsToLineCount(let minimum, let maximum):
            return BlockInputEditorHeightSizing(
                defaultVisibleLineCount: minimum,
                maximumVisibleLineCount: maximum
            )
        case .fixedLineCount(let lineCount):
            // Equal default and maximum keep the reported height constant, so
            // adding or removing lines never resizes the editor; overflow
            // scrolls internally.
            return BlockInputEditorHeightSizing(
                defaultVisibleLineCount: lineCount,
                maximumVisibleLineCount: lineCount,
                onPreferredHeightChange: { height in
                    if fixedHeight != height {
                        fixedHeight = height
                    }
                }
            )
        }
    }

    /// Cmd+Return submits and Escape cancels when the host provides the action;
    /// plain Return stays a newline because every host here is multi-line, unlike
    /// the chat composer.
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

/// Applies `.frame(height:)` only for `.fixedLineCount`; the other sizing modes
/// must leave the editor's own height proposal untouched.
private struct HeightModifier: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height)
        } else {
            content
        }
    }
}
