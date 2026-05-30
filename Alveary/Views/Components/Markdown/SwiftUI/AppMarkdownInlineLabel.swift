import AppKit
import SwiftUI

/// Renders a single-line string that may contain basic inline markdown and/or `@file`
/// mentions (in the composer's stored percent-encoded form). Plain segments render as
/// `Text`; inline-code and mention segments render via `AppMarkdownInlineCodeChip`
/// clamped to the `textStyle`'s line height so each chip's rounded background visually
/// overflows into the surrounding vertical padding without inflating the parent row or
/// tab height.
///
/// Use in place of `Text(...)` for surfaces like sidebar thread rows and conversation tab
/// chips where the source string may contain inline markdown or mentions but the row/tab
/// must keep a uniform height regardless of whether any chip is present.
struct AppMarkdownInlineLabel: View {
    let text: String
    /// The text style that drives both the SwiftUI text font and the inline-code chip
    /// metrics. Using a single value avoids mismatches between chip and surrounding text.
    var textStyle: NSFont.TextStyle = .body

    var body: some View {
        let segments = InlineSegment.displaySegments(for: text)
        // Fast-path: no inline chips, render a plain `Text` so environment
        // modifiers like `.fixedSize` and `.lineLimit` behave exactly as they would on a
        // bare `Text`.
        if segments.count == 1, case .text(let value) = segments[0] {
            Text(value)
                .font(swiftUIFont)
                .lineLimit(1)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let value):
                        Text(value).font(swiftUIFont)
                    case .code(let value), .mention(let value):
                        AppMarkdownInlineCodeChip(text: value, style: .standard, fontSize: chipFontSize)
                            .frame(height: textLineHeight, alignment: .center)
                    }
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        }
    }

    private var swiftUIFont: Font {
        switch textStyle {
        case .largeTitle: return .largeTitle
        case .title1: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption1: return .caption
        case .caption2: return .caption2
        default: return .body
        }
    }

    private var chipFontSize: CGFloat {
        NSFont.preferredFont(forTextStyle: textStyle).pointSize * markdownInlineCodeFontScale
    }

    private var textLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: textStyle)
        return ceil(font.ascender + abs(font.descender) + font.leading)
    }
}

extension AppMarkdownInlineLabel {
    /// Returns `markdown` with inline-code backtick delimiters stripped and `@` mentions
    /// decoded to their human-readable form (`@<basename>`) so the result reads cleanly in
    /// non-markdown contexts like VoiceOver accessibility labels. HTML image tags become
    /// `(Image)` and other HTML-like tags are stripped for compact display surfaces.
    nonisolated static func plainText(from markdown: String) -> String {
        let segments = InlineSegment.displaySegments(for: markdown)
        if segments.count == 1, case .text(let value) = segments[0] {
            return String(value.characters)
        }
        var result = ""
        result.reserveCapacity(markdown.count)
        for segment in segments {
            switch segment {
            case .text(let value):
                result += String(value.characters)
            case .code(let value), .mention(let value):
                result += value
            }
        }
        return result
    }
}

private enum InlineSegment {
    case text(AttributedString)
    case code(String)
    /// A decoded `@<basename>` display label for a file mention. The underlying stored
    /// form may be percent-encoded (e.g. `@/Users/me/My%20File.png`); the decoded
    /// basename is cached on the segment so render and `plainText` don't redo the work.
    case mention(String)

    static func displaySegments(for markdown: String) -> [InlineSegment] {
        let attributed = parsedInlineMarkdown(displayMarkdown(from: markdown))
        var result: [InlineSegment] = []
        for run in attributed.runs {
            let content = AttributedString(attributed[run.range])
            if run.inlinePresentationIntent?.contains(.code) == true {
                result.appendInlineSegment(.code(String(content.characters)))
            } else if run.link != nil {
                result.appendInlineSegment(.text(sanitizedText(content)))
            } else {
                textAndMentionSegments(in: content).forEach { result.appendInlineSegment($0) }
            }
        }
        return result
    }

    private static func displayMarkdown(from markdown: String) -> String {
        appMarkdownCompactDisplaySource(from: markdown)
    }

    private static func parsedInlineMarkdown(_ markdown: String) -> AttributedString {
        guard mayContainInlineMarkdown(markdown) else {
            return AttributedString(markdown)
        }
        let parser = AppMarkdownParser(parsingMode: .inline)
        return (try? parser.attributedString(for: markdown)) ?? AttributedString(markdown)
    }

    private static func mayContainInlineMarkdown(_ markdown: String) -> Bool {
        markdown.contains { character in
            switch character {
            case "`", "[", "*", "_", "<", "!", "\\":
                return true
            default:
                return false
            }
        }
    }

    private static func textAndMentionSegments(in content: AttributedString) -> [InlineSegment] {
        let text = String(content.characters)
        let mentions = ChatComposerTextSupport.fileMentionMatches(in: text)
        guard !mentions.isEmpty else {
            return [.text(sanitizedText(content))]
        }

        var result: [InlineSegment] = []
        var cursor = 0
        for mention in mentions {
            let range = mention.highlightRange
            if range.location > cursor,
               let prefixRange = attributedRange(
                for: NSRange(location: cursor, length: range.location - cursor),
                in: content
               ) {
                result.appendInlineSegment(.text(sanitizedText(AttributedString(content[prefixRange]))))
            }

            result.appendInlineSegment(
                .mention(
                    CanonicalPath.decodeStoredMentionPath(
                        ChatComposerTextSupport.mentionChipDisplayText(for: mention.path)
                    )
                )
            )
            cursor = NSMaxRange(range)
        }

        let sourceLength = (text as NSString).length
        if cursor < sourceLength,
           let suffixRange = attributedRange(
            for: NSRange(location: cursor, length: sourceLength - cursor),
            in: content
           ) {
            result.appendInlineSegment(.text(sanitizedText(AttributedString(content[suffixRange]))))
        }
        return result
    }

    private static func sanitizedText(_ content: AttributedString) -> AttributedString {
        var sanitized = content
        let ranges = sanitized.runs.map(\.range)
        for range in ranges {
            sanitized[range].link = nil
        }
        return sanitized
    }

    private static func attributedRange(
        for nsRange: NSRange,
        in attributedString: AttributedString
    ) -> Range<AttributedString.Index>? {
        let flatString = String(attributedString.characters)
        guard nsRange.location >= 0,
              nsRange.location + nsRange.length <= (flatString as NSString).length,
              let swiftRange = Range(nsRange, in: flatString),
              let lowerScalar = swiftRange.lowerBound.samePosition(in: flatString.unicodeScalars),
              let upperScalar = swiftRange.upperBound.samePosition(in: flatString.unicodeScalars),
              let lowerAttr = AttributedString.Index(lowerScalar, within: attributedString),
              let upperAttr = AttributedString.Index(upperScalar, within: attributedString) else {
            return nil
        }
        return lowerAttr..<upperAttr
    }
}

private extension Array where Element == InlineSegment {
    mutating func appendInlineSegment(_ segment: InlineSegment) {
        guard !segment.isEmpty else {
            return
        }

        if case .text(let existing) = last,
           case .text(let value) = segment {
            removeLast()
            var combined = existing
            combined += value
            append(.text(combined))
        } else {
            append(segment)
        }
    }
}

private extension InlineSegment {
    var isEmpty: Bool {
        switch self {
        case .text(let value):
            return value.characters.isEmpty
        case .code(let value), .mention(let value):
            return value.isEmpty
        }
    }
}
