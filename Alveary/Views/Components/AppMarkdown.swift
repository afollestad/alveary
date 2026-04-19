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
        attachComposerChips(to: &attributedString)
        return attributedString
    }

    // Attach composer-style chips (leading `/command`, `@file/mention`) inside rendered user
    // messages. The markdown parser runs first, so `attributedString` is already stripped of
    // backtick delimiters — we detect on the flattened parsed string so NSRange offsets align
    // directly with the attributed-string content.
    //
    // Rendering strategy mirrors inline code: replace the source range with the chip's
    // display text and tag it with `.inlinePresentationIntent.code`. Textual's inline style
    // then renders the run as a flat monospaced highlight — no attachment, no `Canvas`
    // placeholder, so chips don't grow the line they sit on. This matches the inline-code
    // treatment exactly and keeps multi-line user bubbles uniform.
    //
    // The conflict check skips ranges that already carry a Textual attachment (e.g. image or
    // emoji attachments from `WithAttachments`), a markdown `.link`, a `.codeBlock`
    // presentation intent (fenced code block), or a `.code` inline presentation intent
    // (markdown inline code). The inline-code check is load-bearing: `composerTextChips` is
    // called here with the *parsed* flat string (backticks already stripped), so the
    // function's internal `codeRanges`-based exclusion finds nothing to exclude. Without
    // this guard, a user writing `` `@path/to/file.swift` `` in a message would have their
    // inline code clobbered by a composer chip that truncates the path to just `@file.swift`.
    //
    // Chips are processed in reverse order by `range.location` so each substitution can
    // mutate characters after the chip without invalidating the NSRange of earlier
    // (lower-indexed) chips. Indices into the attributed string are re-derived from the
    // freshly flattened string on every iteration because the underlying
    // `AttributedString.Index` values cannot be reused after a substitution shifts content.
    private func attachComposerChips(to attributedString: inout AttributedString) {
        guard let composerChipProvider else {
            return
        }

        let initialFlatString = String(attributedString.characters)
        let chips = composerChipProvider(initialFlatString)
            .sorted { $0.range.location > $1.range.location }

        for chip in chips where chip.range.length > 0 {
            guard let attributedRange = resolveAttributedRange(for: chip.range, in: attributedString),
                  !runsConflictWithComposerChip(in: attributedString[attributedRange].runs) else {
                continue
            }
            applyComposerChip(chip, to: &attributedString, at: attributedRange)
        }
    }

    private func resolveAttributedRange(
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

    private func runsConflictWithComposerChip(
        in runs: AttributedString.Runs
    ) -> Bool {
        runs.contains { run in
            if run.textual.attachment != nil { return true }
            if run.link != nil { return true }
            if run.presentationIntent?.components.contains(where: { component in
                if case .codeBlock = component.kind { return true }
                return false
            }) == true {
                return true
            }
            if run.inlinePresentationIntent?.contains(.code) == true { return true }
            return false
        }
    }

    private func applyComposerChip(
        _ chip: AppTextEditorChip,
        to attributedString: inout AttributedString,
        at attributedRange: Range<AttributedString.Index>
    ) {
        // Preserve the enclosing paragraph's block-level `presentationIntent` on the
        // replacement so Textual doesn't treat the inserted run as a standalone block
        // and break flow with a line break before or after the chip.
        let preservedPresentationIntent = attributedString[attributedRange].runs
            .compactMap { $0.presentationIntent }
            .first
        var replacement = AttributedString(chip.displayText)
        replacement.inlinePresentationIntent = .code
        if let preservedPresentationIntent {
            replacement.presentationIntent = preservedPresentationIntent
        }
        attributedString.replaceSubrange(attributedRange, with: replacement)
    }
}

// Renders an inline rounded chip used by `AppMarkdownInlineLabel` — single-line surfaces
// such as sidebar thread rows, conversation tab chips, and terminal session chips — where
// the chip overflows into the parent's vertical padding without inflating row/tab height.
// Multi-line bubble surfaces do *not* use this view; they render inline code and composer
// chips as flat monospaced highlights via Textual's native inline-code styling, which
// keeps line heights uniform (see `AppMarkdownParser.attachComposerChips(to:)`).
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
        .textual.blockSpacing(.init(top: 8, bottom: 12))
    }
}
