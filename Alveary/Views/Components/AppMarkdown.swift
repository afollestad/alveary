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
        // NOTE: Do not call `.textual.structuredTextStyle(.default)` here. It reinstates the
        // built-in inline style (with a blue link color) and clobbers our accent-colored
        // `.link(...)` override. Leave the individual environment modifiers below in place —
        // Textual already defaults the remaining block styles to their `.default` values.
        StructuredText(markdown, parser: AppMarkdownParser(baseURL: baseURL, inlineCodeStyle: inlineCodeStyle))
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

// Textual's `DynamicColor` accepts either a single `Color` variant or explicit light/dark
// `Color`s. Prefer the light/dark form and flatten the palette's dynamic `NSColor` once
// per appearance rather than wrapping a single dynamic `Color`: `DynamicColor(Color(...))`
// would depend on SwiftUI preserving the NSColor's `dynamicProvider` through its
// `Color`-to-`NSColor` bridge at draw time, which is an implicit contract. Flattening here
// keeps the scheme switch inside `DynamicColor`'s own light/dark branch. Trade-off: macOS
// system-accent changes made mid-session are not reflected in Textual-rendered chips until
// the app restarts; the asset-catalog `AccentColor` (default "Multicolor" preference) is
// static per launch, so this has no practical effect for the common case.
//
// `NSAppearance` is not `Sendable`, so the two built-in appearances are constructed
// inside this function on each call rather than cached in module-level `let`s. The
// helper is only invoked a handful of times at module initialization, so the extra
// lookups are negligible.
private func dynamicColor(from nsColor: NSColor) -> DynamicColor {
    guard let aqua = NSAppearance(named: .aqua),
          let darkAqua = NSAppearance(named: .darkAqua) else {
        let fallback = Color(nsColor: nsColor)
        return DynamicColor(light: fallback, dark: fallback)
    }
    return DynamicColor(
        light: Color(nsColor: nsColor.resolved(for: aqua)),
        dark: Color(nsColor: nsColor.resolved(for: darkAqua))
    )
}

internal let appMarkdownInlineStyle = InlineStyle.default
    .code(
        .monospaced,
        .fontScale(markdownInlineCodeFontScale),
        .backgroundColor(dynamicColor(from: AppMarkdownCodeBlockPalette.inlineFillNSColor))
    )
    .link(.foregroundColor(Color.accentColor))

// Links inside user bubbles must not be accent-colored: the bubble fill is
// `AppSelectionStyle.rowFill` (itself an accent tint), so accent-on-accent links would
// clash with the fill in both schemes. Match the bubble's `.primary` body color so links
// inherit the same label treatment as the rest of the bubble text.
private let appMarkdownUserBubbleInlineStyle = InlineStyle.default
    .code(
        .monospaced,
        .fontScale(markdownInlineCodeFontScale),
        .foregroundColor(dynamicColor(from: AppMarkdownCodeBlockPalette.userBubbleInlineForegroundNSColor)),
        .backgroundColor(dynamicColor(from: AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor))
    )
    .link(.foregroundColor(Color.primary))

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
            return AppMarkdownCodeBlockPalette.inlineFillNSColor
        case .userBubble:
            return AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor
        }
    }

    private var foregroundColor: NSColor {
        switch style {
        case .standard:
            return AppMarkdownCodeBlockPalette.inlineForegroundNSColor
        case .userBubble:
            return AppMarkdownCodeBlockPalette.userBubbleInlineForegroundNSColor
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

    // Accent-tinted chip background; reads from the asset-catalog `AccentColor` via
    // `NSColor.controlAccentColor` and layers at low opacity so chips tint their parent
    // surface without overpowering surrounding text. Light mode bumps the opacity so the
    // fill still reads as amber against a white parent background instead of washing out
    // to near-white. Cached as a single dynamic NSColor so repeated accesses return the
    // same instance — important for NSColor equality in attributed-string attributes.
    static let inlineFillNSColor: NSColor = .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent.withAlphaComponent(0.22)
        default:
            return accent.withAlphaComponent(0.40)
        }
    }

    // Solid accent in dark mode reads well against the low-opacity tint, but in light
    // mode the same bright accent over a tinted fill loses contrast; blend the accent
    // toward black so the chip text stays legible. Deriving from `controlAccentColor`
    // keeps the foreground in sync with the `AccentColor` asset — swapping the asset to
    // a different hue produces a matching darkened foreground automatically.
    static let inlineForegroundNSColor: NSColor = .accentDerived { accent, appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return accent
        default:
            return accent.blended(withFraction: 0.70, of: .black) ?? accent
        }
    }

    // Neutral-gray chip fill used when the chip sits on an accent-tinted surface (user
    // bubble, selected sidebar row, selected conversation tab). The parent surface is
    // `AppSelectionStyle.rowFill`, which is already an accent tint — another accent-derived
    // fill at low opacity reads as "the same color as the background" and fails contrast,
    // especially in light mode where rowFill is a near-saturated accent. A grayscale fill
    // breaks the accent-on-accent pattern and gives the chip a clearly distinct surface.
    // Light mode uses a near-white gray (so `.labelColor` black text pops); dark mode uses
    // a medium-dark gray (so `.labelColor` white text pops). Do not reintroduce a
    // `labelColor.withAlphaComponent(...)` fill here — it looks correct on darker accents
    // but vanishes into bright accent surfaces.
    //
    // Built with a raw `NSColor(name:dynamicProvider:)` rather than `.accentDerived(...)`
    // because the resolved value does not depend on the system accent — it's a pure
    // grayscale swatch. The `.accentDerived` helper's `performAsCurrentDrawingAppearance`
    // flattening is only load-bearing when the transform consumes `controlAccentColor`.
    static let userBubbleInlineFillNSColor: NSColor = NSColor(name: nil, dynamicProvider: { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 0.25, alpha: 1.0)
        default:
            return NSColor(white: 0.93, alpha: 1.0)
        }
    })

    static let userBubbleInlineForegroundNSColor: NSColor = NSColor.labelColor

    static func borderNSColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(srgbRed: 0.26, green: 0.27, blue: 0.31, alpha: 1)
        default:
            return NSColor(srgbRed: 0.87, green: 0.87, blue: 0.90, alpha: 1)
        }
    }
}
