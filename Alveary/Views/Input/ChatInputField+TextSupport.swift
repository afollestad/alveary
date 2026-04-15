import Foundation
import SwiftUI

enum ChatInputFieldTextSupport {
    struct FileMentionMatch: Equatable {
        let range: NSRange
        let highlightRange: NSRange
        let path: String
    }

    private static let fileMentionPattern = #"(^|[\s\(\[\{<"'])@([^\s\)\]\}>"']+)"#
    private static let fileMentionRegex = try? NSRegularExpression(pattern: fileMentionPattern)

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

        guard let startOffset = offset(of: tokenStartIndex, in: text) else {
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
        textSelection: TextSelection?
    ) -> Int? {
        guard let textSelection else {
            return textLength(in: text)
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
            let end = textLength(in: text)
            return end..<end
        }

        switch textSelection.indices {
        case .selection(let range):
            guard let lowerBound = offset(of: range.lowerBound, in: text),
                  let upperBound = offset(of: range.upperBound, in: text) else {
                return nil
            }
            return lowerBound..<upperBound
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
        let insertionOffset = offsets.lowerBound + textLength(in: inserted)
        return (newText, insertionOffset)
    }

    static func normalizedMentionPath(for path: String, relativeTo workingDirectory: String?) -> String {
        CanonicalPath.normalizeMentionPath(path, relativeTo: workingDirectory)
    }

    static func fileMentionMatches(in text: String) -> [FileMentionMatch] {
        guard text.contains("@"),
              let fileMentionRegex else {
            return []
        }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)

        return fileMentionRegex.matches(in: text, range: fullRange).compactMap { match in
            guard match.numberOfRanges >= 3 else {
                return nil
            }

            let fullMatchRange = match.range
            let prefixRange = match.range(at: 1)
            let pathRange = match.range(at: 2)
            guard fullMatchRange.location != NSNotFound,
                  prefixRange.location != NSNotFound,
                  pathRange.location != NSNotFound else {
                return nil
            }

            let highlightStart = prefixRange.location + prefixRange.length
            let highlightEnd = pathRange.location + pathRange.length
            guard highlightEnd > highlightStart else {
                return nil
            }

            return FileMentionMatch(
                range: fullMatchRange,
                highlightRange: NSRange(location: highlightStart, length: highlightEnd - highlightStart),
                path: source.substring(with: pathRange)
            )
        }
    }

    static func highlightedTokenRanges(in text: String) -> [NSRange] {
        var ranges = fileMentionMatches(in: text).map(\.highlightRange)

        if let slashCommandRange = leadingSlashCommandRange(in: text) {
            ranges.insert(slashCommandRange, at: 0)
        }

        return ranges
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

    static func offset(of index: String.Index, in text: String) -> Int? {
        let utf16 = text.utf16
        guard let utf16Index = index.samePosition(in: utf16) else {
            return nil
        }
        return utf16.distance(from: utf16.startIndex, to: utf16Index)
    }

    static func index(at offset: Int, in text: String) -> String.Index {
        let utf16 = text.utf16
        let clampedOffset = min(max(0, offset), utf16.count)
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: clampedOffset)
        return String.Index(utf16Index, within: text) ?? text.endIndex
    }

    private static func leadingSlashCommandRange(in text: String) -> NSRange? {
        guard text.first == "/" else {
            return nil
        }

        var endIndex = text.index(after: text.startIndex)
        while endIndex < text.endIndex,
              !isTokenBoundary(text[endIndex]) {
            endIndex = text.index(after: endIndex)
        }

        guard let endOffset = offset(of: endIndex, in: text), endOffset > 0 else {
            return nil
        }

        // Slash commands only activate from the front of the message, so only color the leading token.
        return NSRange(location: 0, length: endOffset)
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
        character.isWhitespace || ["(", "[", "{", "<", "\"", "'"].contains(character)
    }

    private static func textLength(in text: String) -> Int {
        text.utf16.count
    }
}
