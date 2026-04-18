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
    var composerChipProvider: ((String) -> [AppTextEditorChip])?

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
        StructuredText(
            markdown,
            parser: AppMarkdownParser(
                baseURL: baseURL,
                inlineCodeStyle: inlineCodeStyle,
                composerChipProvider: composerChipProvider
            )
        )
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
    let composerChipProvider: ((String) -> [AppTextEditorChip])?
    var parsingMode: AppMarkdownParsingMode = .structured

    init(
        baseURL: URL? = nil,
        inlineCodeStyle: AppMarkdownInlineCodeStyle = .standard,
        composerChipProvider: ((String) -> [AppTextEditorChip])? = nil,
        parsingMode: AppMarkdownParsingMode = .structured
    ) {
        self.baseURL = baseURL
        self.inlineCodeStyle = inlineCodeStyle
        self.composerChipProvider = composerChipProvider
        self.parsingMode = parsingMode
    }

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
        attachComposerChips(to: &attributedString)
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

    // Attach composer-style chips (leading `/command`, `@file/mention`) inside rendered user
    // messages. The markdown parser runs first, so `attributedString` is already stripped of
    // backtick delimiters — we detect on the flattened parsed string so NSRange offsets align
    // directly with the attributed-string content. Ranges that already carry an inline-code
    // attachment (from `attachInlineCodeChips`), a fenced-code-block presentation intent, or
    // a markdown link are skipped so we don't clobber those renderings.
    private func attachComposerChips(to attributedString: inout AttributedString) {
        guard let composerChipProvider else {
            return
        }

        let flatString = String(attributedString.characters)
        let chips = composerChipProvider(flatString)

        for chip in chips {
            guard chip.range.length > 0,
                  let swiftRange = Range(chip.range, in: flatString),
                  let lowerScalar = swiftRange.lowerBound.samePosition(in: flatString.unicodeScalars),
                  let upperScalar = swiftRange.upperBound.samePosition(in: flatString.unicodeScalars),
                  let lowerAttr = AttributedString.Index(lowerScalar, within: attributedString),
                  let upperAttr = AttributedString.Index(upperScalar, within: attributedString) else {
                continue
            }

            let attributedRange = lowerAttr..<upperAttr
            let conflictsWithExistingRun = attributedString[attributedRange].runs.contains { run in
                if run.textual.attachment != nil {
                    return true
                }
                if run.link != nil {
                    return true
                }
                if let intent = run.presentationIntent,
                   intent.components.contains(where: { component in
                       if case .codeBlock = component.kind {
                           return true
                       }
                       return false
                   }) {
                    return true
                }
                return false
            }
            guard !conflictsWithExistingRun else {
                continue
            }

            let attachment = AppMarkdownInlineCodeAttachment(
                text: chip.displayText,
                style: inlineCodeStyle
            )
            attributedString[attributedRange].textual.attachment = AnyAttachment(attachment)
        }
    }
}

// Renders an inline rounded chip for both parser-detected inline code runs and
// composer-style chips (leading `/command`, `@file/mention`). Both call sites draw the
// same chip view, so they share the attachment: inline code passes the backtick contents
// as `text`, while composer chips pass the already-shortened display label.
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
