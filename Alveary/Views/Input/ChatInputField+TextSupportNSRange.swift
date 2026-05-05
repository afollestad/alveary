import Foundation

/// `NSRange` overloads for the native AppKit composer.
///
/// AppKit text selection is reported in UTF-16 offsets, while the original
/// SwiftUI composer helpers use `TextSelection`. Keep native autocomplete,
/// drag-drop insertion, and inline slash hints on this path so selection
/// validation stays consistent with `NSTextView`.
extension ChatInputFieldTextSupport {
    static func activeCompletionToken(
        text: String,
        selectedRange: NSRange?
    ) -> ComposerCompletionToken? {
        guard let insertionOffset = insertionPointOffset(text: text, selectedRange: selectedRange) else {
            return nil
        }

        let caretIndex = index(at: insertionOffset, in: text)
        let tokenStartIndex = nsRangeTokenStart(before: caretIndex, in: text)
        let token = String(text[tokenStartIndex..<caretIndex])

        guard let trigger = token.first,
              let startOffset = offset(of: tokenStartIndex, in: text) else {
            return nil
        }
        switch trigger {
        case "@":
            return ComposerCompletionToken(
                kind: .file,
                replacementOffsets: startOffset..<insertionOffset,
                query: String(token.dropFirst())
            )
        case "/":
            guard tokenStartIndex == text.startIndex else {
                return nil
            }
            return ComposerCompletionToken(
                kind: .skill,
                replacementOffsets: startOffset..<insertionOffset,
                query: String(token.dropFirst())
            )
        default:
            return nil
        }
    }

    static func insertionPointOffset(
        text: String,
        selectedRange: NSRange?
    ) -> Int? {
        guard let selectedRange else {
            return nsRangeTextLength(in: text)
        }

        let textLength = nsRangeTextLength(in: text)
        guard selectedRange.length == 0,
              selectedRange.location >= 0,
              selectedRange.location <= textLength else {
            return nil
        }
        return selectedRange.location
    }

    static func editableSelectionOffsets(
        text: String,
        selectedRange: NSRange?
    ) -> Range<Int>? {
        guard let selectedRange else {
            let end = nsRangeTextLength(in: text)
            return end..<end
        }

        let textLength = nsRangeTextLength(in: text)
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              NSMaxRange(selectedRange) <= textLength else {
            return nil
        }
        return selectedRange.location..<NSMaxRange(selectedRange)
    }

    static func inlineSlashCommandHint(
        in text: String,
        selectedRange: NSRange?,
        isInputFocused: Bool,
        commandHints: [String: String]
    ) -> String? {
        guard let slashCommandMatch = leadingSlashCommandMatch(in: text),
              !slashCommandMatch.name.isEmpty,
              nsRangeContainsOnlyInlineHintWhitespace(slashCommandMatch.trailingText),
              nsRangeInlineHintSelectionEligible(
                  text: text,
                  selectedRange: selectedRange,
                  isInputFocused: isInputFocused
              ),
              let hint = commandHints[slashCommandMatch.name],
              !hint.isEmpty else {
            return nil
        }

        return slashCommandMatch.trailingText.isEmpty ? " " + hint : hint
    }

    private static func nsRangeTokenStart(before index: String.Index, in text: String) -> String.Index {
        var current = index
        while current > text.startIndex {
            let previous = text.index(before: current)
            if nsRangeIsTokenBoundary(text[previous]) {
                return text.index(after: previous)
            }
            current = previous
        }
        return text.startIndex
    }

    private static func nsRangeIsTokenBoundary(_ character: Character) -> Bool {
        character.isWhitespace || ["(", "[", "{", "<", "\"", "'"].contains(character)
    }

    private static func nsRangeInlineHintSelectionEligible(
        text: String,
        selectedRange: NSRange?,
        isInputFocused: Bool
    ) -> Bool {
        guard isInputFocused else {
            return false
        }

        guard let selectedRange else {
            return true
        }

        let textEnd = nsRangeTextLength(in: text)
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              NSMaxRange(selectedRange) <= textEnd else {
            // The native editor can briefly report a stale selection while SwiftUI
            // state clears or restores the draft. Keep the hint hidden until the
            // next valid selection arrives.
            return false
        }
        return selectedRange.length == 0 && selectedRange.location == textEnd
    }

    private static func nsRangeContainsOnlyInlineHintWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private static func nsRangeTextLength(in text: String) -> Int {
        text.utf16.count
    }
}
