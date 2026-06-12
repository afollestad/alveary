@preconcurrency import AppKit
import Foundation
import SwiftUI

private let transcriptToolSummarySlashCommandPattern = #"(^|[\s\(\[\{<"'])(/[A-Za-z][A-Za-z0-9_-]*)(?=$|[\s\)\]\}>"'.,;:])"#
private let toolSummaryInlineCodeFillOpacity: CGFloat = 0.08

/// Shared tool-summary formatter for SwiftUI and AppKit rows. Keep chip detection here
/// so the two transcript renderers stay aligned while rows migrate incrementally.
@MainActor
enum TranscriptToolSummaryFormatter {
    static func attributedString(_ text: String, typography: TranscriptTypography) -> AttributedString {
        var attributed = attributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = typography.codeFont
        }
        return attributed
    }

    static func nsAttributedString(_ text: String, typography: TranscriptTypography) -> NSAttributedString {
        let attributed = NSMutableAttributedString(attributedString: AppKitMarkdownAttributedStringBuilder.attributedString(
            from: attributedString(text),
            baseFont: typography.nsFont(.inlineToolText),
            inlineCodeFont: typography.inlineToolCodeNSFont,
            inlineCodeStyle: .standard
        ))
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.foregroundColor, value: transcriptInlineToolRowColor, range: fullRange)
        attributed.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            guard value != nil else {
                return
            }
            attributed.addAttribute(
                .backgroundColor,
                value: transcriptInlineToolRowColor.withAlphaComponent(toolSummaryInlineCodeFillOpacity),
                range: range
            )
        }
        return attributed
    }

    private static func attributedString(_ text: String) -> AttributedString {
        if let cached = AttributedSummaryCache.cache[text] {
            return cached
        }

        let result: AttributedString
        let parser = AppMarkdownParser(
            composerChipProvider: toolSummaryTextChips(in:),
            parsingMode: .inline
        )
        if var attributed = try? parser.attributedString(for: text) {
            applyInlineChipStyle(to: &attributed)
            result = attributed
        } else {
            result = AttributedString(text)
        }

        AttributedSummaryCache.cache[text] = result
        return result
    }

    private static func applyInlineChipStyle(to attributed: inout AttributedString) {
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].backgroundColor = Color.secondary.opacity(Double(toolSummaryInlineCodeFillOpacity))
        }
    }

    private static func toolSummaryTextChips(in text: String) -> [AppTextEditorChip] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: text)
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges
        let source = text as NSString

        var chips = ChatComposerTextSupport.fileMentionMatches(in: text).map { match in
            AppTextEditorChip(
                range: match.highlightRange,
                displayText: ChatComposerTextSupport.mentionChipDisplayText(for: match.path),
                style: .fileMention
            )
        }

        if let slashCommandRegex = AttributedSummaryCache.slashCommandRegex {
            let fullRange = NSRange(location: 0, length: source.length)
            chips.append(contentsOf: slashCommandRegex.matches(in: text, range: fullRange).compactMap { match in
                guard match.numberOfRanges >= 3 else {
                    return nil
                }
                let commandRange = match.range(at: 2)
                guard commandRange.location != NSNotFound else {
                    return nil
                }
                return AppTextEditorChip(
                    range: commandRange,
                    displayText: source.substring(with: commandRange),
                    style: .slashCommand
                )
            })
        }

        return chips
            .filter { chip in
                !excludedRanges.contains { NSIntersectionRange($0, chip.range).length > 0 }
            }
            .sorted { $0.range.location < $1.range.location }
    }
}

@MainActor
private enum AttributedSummaryCache {
    static var cache: [String: AttributedString] = [:]
    static let slashCommandRegex = try? NSRegularExpression(pattern: transcriptToolSummarySlashCommandPattern)
}
