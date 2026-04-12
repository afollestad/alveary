import Foundation
import SwiftUI

enum ChatInputFieldTextSupport {
    static func activeCompletionToken(
        text: String,
        textSelection: TextSelection?
    ) -> ComposerCompletionToken? {
        guard let insertionOffset = insertionPointOffset(text: text, textSelection: textSelection) else {
            return nil
        }

        let caretIndex = index(at: insertionOffset, in: text)
        let tokenStartIndex = tokenStart(before: caretIndex, in: text)
        let token = String(text[tokenStartIndex..<caretIndex])

        guard let trigger = token.first else {
            return nil
        }

        let startOffset = offset(of: tokenStartIndex, in: text)
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
        textSelection: TextSelection?
    ) -> Int? {
        guard let textSelection else {
            return text.count
        }

        switch textSelection.indices {
        case .selection(let range):
            guard range.lowerBound == range.upperBound else {
                return nil
            }
            return offset(of: range.lowerBound, in: text)
        case .multiSelection:
            return nil
        @unknown default:
            return nil
        }
    }

    static func editableSelectionOffsets(
        text: String,
        textSelection: TextSelection?
    ) -> Range<Int>? {
        guard let textSelection else {
            let end = text.count
            return end..<end
        }

        switch textSelection.indices {
        case .selection(let range):
            return offset(of: range.lowerBound, in: text)..<offset(of: range.upperBound, in: text)
        case .multiSelection:
            return nil
        @unknown default:
            return nil
        }
    }

    static func replacingText(
        in sourceText: String,
        offsets: Range<Int>,
        with replacement: String,
        appendTrailingSpace: Bool,
        ensureLeadingSpace: Bool = false
    ) -> (text: String, insertionOffset: Int) {
        var inserted = replacement
        let lowerIndex = index(at: offsets.lowerBound, in: sourceText)
        let upperIndex = index(at: offsets.upperBound, in: sourceText)

        if ensureLeadingSpace,
           offsets.lowerBound > 0 {
            let previousIndex = index(at: offsets.lowerBound - 1, in: sourceText)
            if !sourceText[previousIndex].isWhitespace {
                inserted = " " + inserted
            }
        }

        let needsTrailingSpace = upperIndex == sourceText.endIndex ||
            (!sourceText[upperIndex].isWhitespace && sourceText[upperIndex] != ".")
        if appendTrailingSpace, needsTrailingSpace {
            inserted += " "
        }

        var newText = sourceText
        newText.replaceSubrange(lowerIndex..<upperIndex, with: inserted)
        let insertionOffset = offsets.lowerBound + inserted.count
        return (newText, insertionOffset)
    }

    static func normalizedMentionPath(for path: String, relativeTo workingDirectory: String?) -> String {
        CanonicalPath.normalizeMentionPath(path, relativeTo: workingDirectory)
    }

    static func modelLabel(for value: String) -> String {
        switch value {
        case "default":
            return "Default"
        case "opus":
            return "Opus"
        case "sonnet":
            return "Sonnet"
        case "haiku":
            return "Haiku"
        default:
            return value
        }
    }

    static func effortLabel(for value: String) -> String {
        switch value {
        case "low":
            return "Low"
        case "medium":
            return "Medium"
        case "high":
            return "High"
        case "max":
            return "Max"
        default:
            return value.capitalized
        }
    }

    static func progressLabel(for reason: ComposerMode.ProgressReason) -> String {
        switch reason {
        case .initialSetup:
            return "Preparing the first turn..."
        case .reconfiguringSession:
            return "Applying session changes..."
        }
    }

    static func offset(of index: String.Index, in text: String) -> Int {
        text.distance(from: text.startIndex, to: index)
    }

    static func index(at offset: Int, in text: String) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(0, offset), text.count))
    }

    private static func tokenStart(before index: String.Index, in text: String) -> String.Index {
        var current = index
        while current > text.startIndex {
            let previous = text.index(before: current)
            if isTokenBoundary(text[previous]) {
                return text.index(after: previous)
            }
            current = previous
        }
        return text.startIndex
    }

    private static func isTokenBoundary(_ character: Character) -> Bool {
        character.isWhitespace || ["(", ")", "[", "]", "{", "}", "<", ">", "\"", "'", ",", ":", ";"].contains(character)
    }
}
