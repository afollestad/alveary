import AppKit
import SwiftUI

/// Renders a single-line string that may contain inline markdown code spans and/or
/// `@file` mentions (in the composer's stored percent-encoded form). Plain segments render
/// as `Text`; inline-code and mention segments render via `AppMarkdownInlineCodeChip`
/// clamped to the `textStyle`'s line height so each chip's rounded background visually
/// overflows into the surrounding vertical padding without inflating the parent row or
/// tab height.
///
/// Use in place of `Text(...)` for surfaces like sidebar thread rows and conversation tab
/// chips where the source string may contain `` ` backticks `` or mentions but the
/// row/tab must keep a uniform height regardless of whether any chip is present.
struct AppMarkdownInlineLabel: View {
    let text: String
    /// The text style that drives both the SwiftUI text font and the inline-code chip
    /// metrics. Using a single value avoids mismatches between chip and surrounding text.
    var textStyle: NSFont.TextStyle = .body

    var body: some View {
        let segments = InlineSegment.segments(for: text)
        // Fast-path: no inline code or mentions, render a plain `Text` so environment
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
                            .fixedSize()
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
    /// non-markdown contexts like VoiceOver accessibility labels. Non-chip content is
    /// preserved verbatim.
    nonisolated static func plainText(from markdown: String) -> String {
        let segments = InlineSegment.segments(for: markdown)
        if segments.count == 1, case .text(let value) = segments[0] {
            return value
        }
        var result = ""
        result.reserveCapacity(markdown.count)
        for segment in segments {
            switch segment {
            case .text(let value), .code(let value), .mention(let value):
                result += value
            }
        }
        return result
    }
}

private enum InlineSegment {
    case text(String)
    case code(String)
    /// A decoded `@<basename>` display label for a file mention. The underlying stored
    /// form may be percent-encoded (e.g. `@/Users/me/My%20File.png`); the decoded
    /// basename is cached on the segment so render and `plainText` don't redo the work.
    case mention(String)

    static func segments(for markdown: String) -> [InlineSegment] {
        let events = chipEvents(in: markdown)
        guard !events.isEmpty else {
            return [.text(markdown)]
        }

        let source = markdown as NSString
        var result: [InlineSegment] = []
        var cursor = 0
        for event in events {
            let range = event.fullRange
            if range.location > cursor {
                let prefix = source.substring(with: NSRange(location: cursor, length: range.location - cursor))
                if !prefix.isEmpty {
                    result.append(.text(prefix))
                }
            }
            result.append(event.asSegment(source: source))
            cursor = NSMaxRange(range)
        }
        if cursor < source.length {
            let suffix = source.substring(with: NSRange(location: cursor, length: source.length - cursor))
            if !suffix.isEmpty {
                result.append(.text(suffix))
            }
        }
        return result
    }

    private static func chipEvents(in markdown: String) -> [ChipEvent] {
        let codeRanges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)

        // Mentions that land inside a fenced block or inline-code span are part of the
        // code literal, not a file reference — skip them so they render as regular
        // code instead of getting double-stylized as a separate mention chip.
        let excludedRanges = codeRanges.blockRanges + codeRanges.inlineFullRanges
        let mentions = ChatInputFieldTextSupport.fileMentionMatches(in: markdown)
            .filter { match in
                !excludedRanges.contains { NSIntersectionRange($0, match.highlightRange).length > 0 }
            }

        var events: [ChipEvent] = []
        events.reserveCapacity(codeRanges.inlineFullRanges.count + mentions.count)
        events.append(contentsOf: zip(codeRanges.inlineFullRanges, codeRanges.inlineContentRanges)
            .map { .code(fullRange: $0.0, contentRange: $0.1) })
        events.append(contentsOf: mentions.map { match in
            ChipEvent.mention(
                range: match.highlightRange,
                displayText: CanonicalPath.decodeStoredMentionPath(
                    ChatInputFieldTextSupport.mentionChipDisplayText(for: match.path)
                )
            )
        })
        events.sort { $0.fullRange.location < $1.fullRange.location }
        return events
    }
}

private enum ChipEvent {
    case code(fullRange: NSRange, contentRange: NSRange)
    case mention(range: NSRange, displayText: String)

    var fullRange: NSRange {
        switch self {
        case .code(let fullRange, _): return fullRange
        case .mention(let range, _): return range
        }
    }

    func asSegment(source: NSString) -> InlineSegment {
        switch self {
        case .code(_, let contentRange):
            return .code(source.substring(with: contentRange))
        case .mention(_, let displayText):
            return .mention(displayText)
        }
    }
}
