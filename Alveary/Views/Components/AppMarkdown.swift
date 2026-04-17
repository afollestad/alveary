@preconcurrency import AppKit
import Foundation
import SwiftUI
import Textual

private let appMarkdownCodeBlockCornerRadius: CGFloat = 8
private let appMarkdownCodeBlockHorizontalPadding: CGFloat = 12
private let appMarkdownCodeBlockVerticalPadding: CGFloat = 10
let markdownInlineCodeFontScale: CGFloat = 0.94
private let appMarkdownInlineCodeCornerRadius: CGFloat = 5
private let appMarkdownInlineCodeHorizontalPadding: CGFloat = 5
private let appMarkdownInlineCodeVerticalPadding: CGFloat = 2

enum AppMarkdownInlineCodeStyle {
    case standard
    case userBubble
}

enum AppMarkdownParsingMode {
    case structured
    case inline
}

struct AppMarkdownText: View {
    let markdown: String
    var baseURL: URL?
    var foregroundColor: Color?
    var inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard

    var body: some View {
        Group {
            if let foregroundColor {
                content
                    .foregroundStyle(foregroundColor)
            } else {
                content
            }
        }
    }

    private var content: some View {
        StructuredText(markdown, parser: AppMarkdownParser(baseURL: baseURL, inlineCodeStyle: inlineCodeStyle))
            .textual.structuredTextStyle(.default)
            .textual.inlineStyle(inlineStyle)
            .textual.codeBlockStyle(AppMarkdownCodeBlockStyle())
            .textual.overflowMode(.scroll)
            .textual.textSelection(.enabled)
    }

    private var inlineStyle: InlineStyle {
        switch inlineCodeStyle {
        case .standard:
            return appMarkdownInlineStyle
        case .userBubble:
            return appMarkdownUserBubbleInlineStyle
        }
    }
}

private let appMarkdownInlineStyle = InlineStyle.default.code(
    .monospaced,
    .fontScale(markdownInlineCodeFontScale),
    .backgroundColor(
        DynamicColor(
            light: Color(nsColor: AppMarkdownCodeBlockPalette.inlineFillNSColor(for: .light)),
            dark: Color(nsColor: AppMarkdownCodeBlockPalette.inlineFillNSColor(for: .dark))
        )
    )
)

private let appMarkdownUserBubbleInlineStyle = InlineStyle.default.code(
    .monospaced,
    .fontScale(markdownInlineCodeFontScale),
    .foregroundColor(
        DynamicColor(
            light: Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineForegroundNSColor(for: .light)),
            dark: Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineForegroundNSColor(for: .dark))
        )
    ),
    .backgroundColor(
        DynamicColor(
            light: Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor(for: .light)),
            dark: Color(nsColor: AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor(for: .dark))
        )
    )
)

struct AppMarkdownParser: MarkupParser {
    let baseURL: URL?
    let inlineCodeStyle: AppMarkdownInlineCodeStyle
    var parsingMode: AppMarkdownParsingMode = .structured

    func attributedString(for input: String) throws -> AttributedString {
        let markdownParser: AttributedStringMarkdownParser
        switch parsingMode {
        case .structured:
            markdownParser = AttributedStringMarkdownParser(baseURL: baseURL)
        case .inline:
            markdownParser = AttributedStringMarkdownParser(
                baseURL: baseURL,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        }

        var attributedString = try markdownParser.attributedString(for: input)
        attachInlineCodeChips(to: &attributedString)
        return attributedString
    }

    private func attachInlineCodeChips(to attributedString: inout AttributedString) {
        let inlineCodeRanges = attributedString.runs.compactMap { run -> (Range<AttributedString.Index>, AppMarkdownInlineCodeAttachment)? in
            guard let intent = run.inlinePresentationIntent,
                  intent.contains(.code) else {
                return nil
            }

            let text = String(attributedString[run.range].characters)
            guard !text.isEmpty else {
                return nil
            }

            return (run.range, AppMarkdownInlineCodeAttachment(text: text, style: inlineCodeStyle))
        }

        for (range, attachment) in inlineCodeRanges {
            attributedString[range].textual.attachment = AnyAttachment(attachment)
        }
    }
}

private struct AppMarkdownInlineCodeAttachment: Attachment {
    let text: String
    let style: AppMarkdownInlineCodeStyle

    var description: String {
        text
    }

    var selectionStyle: AttachmentSelectionStyle {
        .text
    }

    var body: some View {
        AppMarkdownInlineCodeChip(text: text, style: style, fontSize: inlineFont.pointSize)
    }

    func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        let textSize = (text as NSString).size(withAttributes: [.font: inlineFont])
        return CGSize(
            width: ceil(textSize.width) + (appMarkdownInlineCodeHorizontalPadding * 2),
            height: ceil(textSize.height) + (appMarkdownInlineCodeVerticalPadding * 2)
        )
    }

    func baselineOffset(in _: TextEnvironmentValues) -> CGFloat {
        -(inlineFontDescender + appMarkdownInlineCodeVerticalPadding)
    }

    private var inlineFont: NSFont {
        NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * markdownInlineCodeFontScale,
            weight: .regular
        )
    }

    private var inlineFontDescender: CGFloat {
        abs(inlineFont.descender)
    }
}

struct AppMarkdownInlineCodeChip: View {
    let text: String
    let style: AppMarkdownInlineCodeStyle
    let fontSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(nsColor: foregroundColor))
            .padding(.horizontal, appMarkdownInlineCodeHorizontalPadding)
            .padding(.vertical, appMarkdownInlineCodeVerticalPadding)
            .background(Color(nsColor: fillColor))
            .clipShape(RoundedRectangle(cornerRadius: appMarkdownInlineCodeCornerRadius, style: .continuous))
    }

    private var fillColor: NSColor {
        switch style {
        case .standard:
            return AppMarkdownCodeBlockPalette.inlineFillNSColor(for: colorScheme)
        case .userBubble:
            return AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor(for: colorScheme)
        }
    }

    private var foregroundColor: NSColor {
        switch style {
        case .standard:
            return AppMarkdownCodeBlockPalette.inlineForegroundNSColor(for: colorScheme)
        case .userBubble:
            return AppMarkdownCodeBlockPalette.userBubbleInlineForegroundNSColor(for: colorScheme)
        }
    }
}

struct AppMarkdownCodeBlockStyle: StructuredText.CodeBlockStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.225))
                .textual.fontScale(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .padding(.horizontal, appMarkdownCodeBlockHorizontalPadding)
                .padding(.vertical, appMarkdownCodeBlockVerticalPadding)
        }
        .background(AppMarkdownCodeBlockPalette.fillColor(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: appMarkdownCodeBlockCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: appMarkdownCodeBlockCornerRadius, style: .continuous)
                .stroke(AppMarkdownCodeBlockPalette.borderColor(for: colorScheme), lineWidth: 1)
        )
        .textual.blockSpacing(.init(top: 0, bottom: 12))
    }
}

enum AppMarkdownCodeBlockParser {
    static func containsCode(in markdown: String) -> Bool {
        let ranges = codeRanges(in: markdown)
        return !ranges.blockRanges.isEmpty || !ranges.inlineContentRanges.isEmpty
    }

    static func codeRanges(in markdown: String) -> AppMarkdownCodeRanges {
        let blockRanges = blockRanges(in: markdown)
        let inlineRanges = inlineRanges(in: markdown, excluding: blockRanges)
        return AppMarkdownCodeRanges(
            blockRanges: blockRanges,
            inlineFullRanges: inlineRanges.map(\.fullRange),
            inlineContentRanges: inlineRanges.map(\.contentRange),
            inlineDelimiterRanges: inlineRanges.flatMap(\.delimiterRanges)
        )
    }

    static func blockRanges(in markdown: String) -> [NSRange] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        var activeBlockStart: Int?
        var location = 0

        while location < nsMarkdown.length {
            let lineRange = nsMarkdown.lineRange(for: NSRange(location: location, length: 0))
            let line = nsMarkdown.substring(with: lineRange)
            if isFenceLine(line) {
                if let blockStart = activeBlockStart {
                    ranges.append(NSRange(location: blockStart, length: NSMaxRange(lineRange) - blockStart))
                    activeBlockStart = nil
                } else {
                    activeBlockStart = lineRange.location
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let activeBlockStart {
            ranges.append(NSRange(location: activeBlockStart, length: nsMarkdown.length - activeBlockStart))
        }

        return ranges
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
    }

    private static func inlineRanges(in markdown: String, excluding excludedRanges: [NSRange]) -> [AppMarkdownInlineCodeRange] {
        let nsMarkdown = markdown as NSString
        guard nsMarkdown.length > 0 else {
            return []
        }

        var ranges: [AppMarkdownInlineCodeRange] = []
        var location = 0

        while location < nsMarkdown.length {
            if let excludedRange = excludedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = NSMaxRange(excludedRange)
                continue
            }

            guard nsMarkdown.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let delimiterLength = consecutiveBackticks(in: nsMarkdown, from: location)
            let openingLocation = location
            location += delimiterLength

            if let closingLocation = matchingInlineCodeClosingLocation(
                in: nsMarkdown,
                from: location,
                delimiterLength: delimiterLength,
                excluding: excludedRanges
            ) {
                let openingDelimiterRange = NSRange(location: openingLocation, length: delimiterLength)
                let closingDelimiterRange = NSRange(location: closingLocation - delimiterLength, length: delimiterLength)
                let contentRange = NSRange(
                    location: openingLocation + delimiterLength,
                    length: (closingLocation - delimiterLength) - (openingLocation + delimiterLength)
                )
                ranges.append(
                    AppMarkdownInlineCodeRange(
                        fullRange: NSRange(location: openingLocation, length: closingLocation - openingLocation),
                        contentRange: contentRange,
                        delimiterRanges: [openingDelimiterRange, closingDelimiterRange]
                    )
                )
                location = closingLocation
            }

            if location >= nsMarkdown.length || nsMarkdown.character(at: max(location - 1, 0)) != 0x60 {
                location = openingLocation + delimiterLength
            }
        }

        return ranges
    }

    private static func consecutiveBackticks(in markdown: NSString, from location: Int) -> Int {
        var length = 0
        while location + length < markdown.length,
              markdown.character(at: location + length) == 0x60 {
            length += 1
        }
        return max(length, 1)
    }

    private static func matchingInlineCodeClosingLocation(
        in markdown: NSString,
        from startLocation: Int,
        delimiterLength: Int,
        excluding excludedRanges: [NSRange]
    ) -> Int? {
        var location = startLocation

        while location < markdown.length {
            if let excludedRange = excludedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = NSMaxRange(excludedRange)
                continue
            }

            guard markdown.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let closingLength = consecutiveBackticks(in: markdown, from: location)
            guard closingLength == delimiterLength else {
                location += max(closingLength, 1)
                continue
            }

            return location + delimiterLength
        }

        return nil
    }
}

struct AppMarkdownCodeRanges {
    let blockRanges: [NSRange]
    let inlineFullRanges: [NSRange]
    let inlineContentRanges: [NSRange]
    let inlineDelimiterRanges: [NSRange]

    var allRanges: [NSRange] {
        blockRanges + inlineFullRanges + inlineContentRanges + inlineDelimiterRanges
    }
}

private struct AppMarkdownInlineCodeRange {
    let fullRange: NSRange
    let contentRange: NSRange
    let delimiterRanges: [NSRange]
}

enum AppMarkdownCodeBlockPalette {
    static func fillColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: fillNSColor(for: colorScheme))
    }

    static func borderColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: borderNSColor(for: colorScheme))
    }

    static func fillNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        default:
            return NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        }
    }

    static func inlineFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.24, green: 0.26, blue: 0.32, alpha: 1)
        default:
            return NSColor(srgbRed: 0.89, green: 0.91, blue: 0.95, alpha: 1)
        }
    }

    static func inlineForegroundNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
        default:
            return NSColor(srgbRed: 0.16, green: 0.19, blue: 0.24, alpha: 1)
        }
    }

    static func userBubbleInlineFillNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 0.18)
        default:
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.2)
        }
    }

    static func userBubbleInlineForegroundNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
        default:
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98)
        }
    }

    static func borderNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.26, green: 0.27, blue: 0.31, alpha: 1)
        default:
            return NSColor(srgbRed: 0.87, green: 0.87, blue: 0.90, alpha: 1)
        }
    }
}
