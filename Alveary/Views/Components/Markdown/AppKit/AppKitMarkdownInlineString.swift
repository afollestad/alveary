@preconcurrency import AppKit
import Foundation

/// AppKit counterpart to `AppMarkdownInlineParagraph`: turns a raw markdown string into a styled
/// `NSAttributedString` for a single-line `NSTextField`.
///
/// Distinct from `TranscriptToolSummaryFormatter.nsAttributedString`, which additionally chips
/// `/slash-commands` and `@mentions`. Surfaces rendering third-party prose must not use that —
/// a pull request titled `Fix /api/users endpoint` would come back with `/api` in a chip.
@MainActor
enum AppKitMarkdownInlineString {
    static func attributedString(
        for markdown: String,
        baseFont: NSFont,
        foregroundColor: NSColor,
        inlineCodeFill: NSColor = AppMarkdownCodeBlockPalette.inlineFillNSColor
    ) -> NSAttributedString {
        guard appMarkdownMayContainInlineMarkdown(markdown) else {
            // AppKit rows rebuild these on every reconfigure, and a live typography slider
            // reconfigures the whole transcript, so plain strings must not reach the parser.
            return plainString(markdown, baseFont: baseFont, foregroundColor: foregroundColor)
        }

        let parser = AppMarkdownParser(parsingMode: .inline)
        guard let parsed = try? parser.attributedString(
            for: appMarkdownCompactDisplaySource(from: markdown)
        ) else {
            return plainString(markdown, baseFont: baseFont, foregroundColor: foregroundColor)
        }

        let attributed = NSMutableAttributedString(
            attributedString: AppKitMarkdownAttributedStringBuilder.attributedString(
                from: parsed,
                baseFont: baseFont,
                inlineCodeFont: NSFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize * markdownInlineCodeFontScale,
                    weight: .regular
                ),
                inlineCodeStyle: .standard
            )
        )
        let fullRange = NSRange(location: 0, length: attributed.length)
        // The builder hard-writes `.labelColor` across its whole range, so the caller's color has
        // to land after it. The chip fill it wrote is re-tinted the same way.
        attributed.addAttribute(.foregroundColor, value: foregroundColor, range: fullRange)
        attributed.enumerateAttribute(.backgroundColor, in: fullRange) { value, range, _ in
            guard value != nil else {
                return
            }
            attributed.addAttribute(.backgroundColor, value: inlineCodeFill, range: range)
        }
        // `NSTextField.lineBreakMode` does not survive an attributed value, and the builder may
        // carry a paragraph style of its own, so truncation is set here.
        attributed.addAttribute(.paragraphStyle, value: truncatingParagraphStyle, range: fullRange)
        return attributed
    }

    /// The wash for inline code drawn behind already-muted text; see
    /// `markdownMutedInlineCodeFillOpacity`.
    static func mutedInlineCodeFill(over foregroundColor: NSColor) -> NSColor {
        foregroundColor.withAlphaComponent(markdownMutedInlineCodeFillOpacity)
    }

    private static func plainString(
        _ text: String,
        baseFont: NSFont,
        foregroundColor: NSColor
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: foregroundColor,
            .paragraphStyle: truncatingParagraphStyle
        ])
    }

    private static let truncatingParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()
}
