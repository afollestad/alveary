import AppKit
import SwiftUI

/// Renders a single-line string that may contain inline markdown code spans. Plain segments
/// render as `Text`; inline-code segments render via `AppMarkdownInlineCodeChip` clamped to
/// the `textStyle`'s line height so the chip's rounded background visually overflows into
/// the surrounding vertical padding without inflating the parent row or tab height.
///
/// Use in place of `Text(...)` for surfaces like sidebar thread rows and conversation tab
/// chips where the source string may contain `` ` backticks `` but the row/tab must keep a
/// uniform height regardless of whether any code is present.
struct AppMarkdownInlineLabel: View {
    let text: String
    /// The text style that drives both the SwiftUI text font and the inline-code chip
    /// metrics. Using a single value avoids mismatches between chip and surrounding text.
    var textStyle: NSFont.TextStyle = .body

    var body: some View {
        let segments = InlineSegment.segments(for: text)
        // Fast-path: no inline code, render a plain `Text` so environment modifiers like
        // `.fixedSize` and `.lineLimit` behave exactly as they would on a bare `Text`.
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
                    case .code(let value):
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
    /// Returns `markdown` with inline-code backtick delimiters stripped so the result
    /// reads cleanly in non-markdown contexts like VoiceOver accessibility labels.
    /// Non-delimiter content (including the code span's text) is preserved verbatim.
    static func plainText(from markdown: String) -> String {
        let delimiterRanges = AppMarkdownCodeBlockParser
            .codeRanges(in: markdown)
            .inlineDelimiterRanges
            .sorted { $0.location < $1.location }
        guard !delimiterRanges.isEmpty else {
            return markdown
        }

        let nsMarkdown = markdown as NSString
        var result = ""
        result.reserveCapacity(markdown.count)
        var cursor = 0
        for delimiterRange in delimiterRanges {
            if delimiterRange.location > cursor {
                result += nsMarkdown.substring(with: NSRange(
                    location: cursor,
                    length: delimiterRange.location - cursor
                ))
            }
            cursor = NSMaxRange(delimiterRange)
        }
        if cursor < nsMarkdown.length {
            result += nsMarkdown.substring(with: NSRange(
                location: cursor,
                length: nsMarkdown.length - cursor
            ))
        }
        return result
    }
}

private enum InlineSegment {
    case text(String)
    case code(String)

    static func segments(for markdown: String) -> [InlineSegment] {
        let ranges = AppMarkdownCodeBlockParser.codeRanges(in: markdown)
        let pairs = zip(ranges.inlineFullRanges, ranges.inlineContentRanges)
            .sorted { $0.0.location < $1.0.location }
        guard !pairs.isEmpty else {
            return [.text(markdown)]
        }

        let source = markdown as NSString
        var result: [InlineSegment] = []
        var cursor = 0
        for (fullRange, contentRange) in pairs {
            if fullRange.location > cursor {
                let prefix = source.substring(with: NSRange(location: cursor, length: fullRange.location - cursor))
                if !prefix.isEmpty {
                    result.append(.text(prefix))
                }
            }
            result.append(.code(source.substring(with: contentRange)))
            cursor = NSMaxRange(fullRange)
        }
        if cursor < source.length {
            let suffix = source.substring(with: NSRange(location: cursor, length: source.length - cursor))
            if !suffix.isEmpty {
                result.append(.text(suffix))
            }
        }
        return result
    }
}
