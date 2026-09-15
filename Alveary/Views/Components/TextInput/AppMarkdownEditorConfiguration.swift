import AppKit
import BlockInputKit

/// Shared editor behavior for SwiftUI panes and native transcript editing.
@MainActor
enum AppMarkdownEditorConfiguration {
    static func make(
        draft: AppMarkdownDraft,
        placeholder: String,
        sizing: AppMarkdownEditorSizing = .growsToLineCount(minimum: 2, maximum: 10),
        isEditable: Bool = true,
        rawFileMentionChips: Bool = false,
        undoController: BlockInputUndoController? = nil,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDocumentChange: (() -> Void)? = nil,
        onHeightChange: (@MainActor (CGFloat) -> Void)? = nil
    ) -> BlockInputConfiguration {
        BlockInputConfiguration(
            documentStore: draft.store,
            allowsBlockReordering: false,
            allowsDrops: false,
            placeholder: placeholder,
            isEditable: isEditable,
            rawFileMentionChips: rawFileMentionChips,
            style: Self.style,
            heightSizing: heightSizing(sizing, onHeightChange: onHeightChange),
            undoController: undoController,
            keyboardShortcuts: keyboardShortcuts(onSubmit: onSubmit, onCancel: onCancel),
            onDocumentChange: { [weak draft] document in
                Task { @MainActor in
                    draft?.noteDocumentChanged(document)
                    onDocumentChange?()
                }
            }
        )
    }

    private static func heightSizing(
        _ sizing: AppMarkdownEditorSizing,
        onHeightChange: (@MainActor (CGFloat) -> Void)?
    ) -> BlockInputEditorHeightSizing? {
        switch sizing {
        case .fillsAvailableHeight:
            return nil
        case .growsToLineCount(let minimum, let maximum):
            return BlockInputEditorHeightSizing(
                defaultVisibleLineCount: minimum,
                maximumVisibleLineCount: maximum,
                onPreferredHeightChange: onHeightChange
            )
        }
    }

    /// Cmd+Return submits and Escape cancels when the host provides the action;
    /// plain Return stays a newline because every host here is multi-line, unlike
    /// the chat composer.
    private static func keyboardShortcuts(
        onSubmit: (() -> Void)?, onCancel: (() -> Void)?
    ) -> [BlockInputKeyboardShortcut: BlockInputKeyboardShortcutHandler] {
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
