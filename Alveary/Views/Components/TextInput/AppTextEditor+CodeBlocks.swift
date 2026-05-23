@preconcurrency import AppKit
import SwiftUI

// Visual gap between a chip's trailing edge and whatever follows (caret, next
// character, inline hint). Applied as positive `.kern` on the chip's last char,
// which extends that glyph's advance width — so the caret, subsequent typed text,
// and the `AppKitTextView` inline hint all land on the same x, ~3pt past the last
// glyph. Only applied to slash-command chips; file-mention and inline-code chips
// sit mid-line and stay tight. See `applyTextChips(...)` and
// `Alveary/Views/Components/TextInput/AGENTS.md`.
let appTextEditorChipTrailingKern: CGFloat = 3

enum AppTextEditorCodeBlockStyling {
    static let codeBlockHorizontalPadding: CGFloat = 12
    static let codeBlockVerticalPadding: CGFloat = 10
    static let codeBlockOuterGap: CGFloat = 4
    static let codeBlockComposerBreathingRoom: CGFloat = codeBlockOuterGap

    struct StyleContext {
        let fullRange: NSRange
        let highlightRanges: [NSRange]
        let blockRanges: [NSRange]
        let inlineRanges: [NSRange]
        let inlineDelimiterRanges: [NSRange]
        let baseFont: NSFont
        let baseColor: NSColor
        let colorScheme: ColorScheme
    }

    struct TypingContext {
        let selectionRange: NSRange
        let blockRanges: [NSRange]
        let inlineRanges: [NSRange]
        let textUTF16Count: Int
        let baseFont: NSFont
        let baseColor: NSColor
        let colorScheme: ColorScheme
    }

    static func apply(to textStorage: NSTextStorage, context: StyleContext) {
        textStorage.setAttributes(
            baseTypingAttributes(
                font: context.baseFont,
                foregroundColor: context.baseColor
            ),
            range: context.fullRange
        )

        applyBlockStyling(to: textStorage, context: context)
        applyInlineStyling(to: textStorage, context: context)
        applyHighlightStyling(to: textStorage, context: context)
    }

    private static func applyBlockStyling(to textStorage: NSTextStorage, context: StyleContext) {
        let blockCodeRanges = AppMarkdownCodeBlockParser.blockCodeRanges(
            in: textStorage.string,
            matching: context.blockRanges
        )
        if blockCodeRanges.isEmpty {
            for range in context.blockRanges {
                let clampedRange = NSIntersectionRange(range, context.fullRange)
                guard clampedRange.length > 0 else {
                    continue
                }
                textStorage.addAttributes(
                    codeBlockAttributes(font: context.baseFont, colorScheme: context.colorScheme),
                    range: clampedRange
                )
            }
            return
        }

        for range in blockCodeRanges.map(\.contentRange) {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0 else {
                continue
            }
            textStorage.addAttributes(
                codeBlockAttributes(font: context.baseFont, colorScheme: context.colorScheme),
                range: clampedRange
            )
        }

        for blockRange in blockCodeRanges {
            for delimiterRange in blockRange.delimiterRanges {
                let clampedRange = NSIntersectionRange(delimiterRange, context.fullRange)
                guard clampedRange.length > 0 else {
                    continue
                }

                textStorage.addAttributes(
                    codeBlockDelimiterAttributes(
                        font: context.baseFont,
                        isLeadingOpeningDelimiter: delimiterRange == blockRange.delimiterRanges.first &&
                            delimiterRange.location == 0
                    ),
                    range: clampedRange
                )
            }
        }
    }

    static func codeBlockDelimiterAttributes(
        font: NSFont,
        isLeadingOpeningDelimiter: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = 0
        paragraphStyle.tailIndent = 0
        // Leading code blocks do not have visible content above them, so the
        // opening delimiter should reserve only the block's top padding. Keeping
        // the normal outer gap there makes the visual block drop when the first
        // code glyph is inserted.
        let lineHeight: CGFloat
        if isLeadingOpeningDelimiter {
            lineHeight = codeBlockVerticalPadding
        } else {
            // Non-leading opening fences and closing fences are hidden, but
            // still reserve the block edge padding plus the outside gap. If the
            // closing fence collapses completely, text typed below can overlap
            // and clamp the visible code-block chrome.
            lineHeight = codeBlockVerticalPadding + codeBlockOuterGap
        }
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func applyInlineStyling(to textStorage: NSTextStorage, context: StyleContext) {
        for range in context.inlineRanges {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0,
                  !context.blockRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }) else {
                continue
            }
            textStorage.addAttributes(inlineCodeAttributes(font: context.baseFont), range: clampedRange)
        }

        for range in context.inlineDelimiterRanges {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0,
                  !context.blockRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }) else {
                continue
            }
            textStorage.addAttributes(inlineCodeDelimiterAttributes(font: context.baseFont), range: clampedRange)
        }
    }

    private static func applyHighlightStyling(to textStorage: NSTextStorage, context: StyleContext) {
        let highlightColor = NSColor.controlAccentColor
        for range in context.highlightRanges {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0,
                  !context.blockRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }),
                  !context.inlineRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }) else {
                continue
            }
            textStorage.addAttribute(.foregroundColor, value: highlightColor, range: clampedRange)
        }
    }

    static func baseTypingAttributes(
        font: NSFont,
        foregroundColor: NSColor,
        paragraphStyle: NSParagraphStyle = NSMutableParagraphStyle()
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func codeBlockAttributes(
        font: NSFont,
        colorScheme: ColorScheme
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = codeBlockHorizontalPadding
        paragraphStyle.headIndent = codeBlockHorizontalPadding
        paragraphStyle.tailIndent = -codeBlockHorizontalPadding
        paragraphStyle.paragraphSpacingBefore = 0
        paragraphStyle.paragraphSpacing = 0

        return [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular),
            .paragraphStyle: paragraphStyle
        ]
    }

    static func inlineCodeAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular),
            .foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor
        ]
    }

    static func inlineCodeDelimiterAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: max(font.pointSize * 0.38, 4.5), weight: .regular),
            .foregroundColor: NSColor.clear
        ]
    }

    static func typingAttributes(for context: TypingContext) -> [NSAttributedString.Key: Any] {
        let selectedLocation = min(context.selectionRange.location, max(context.textUTF16Count - 1, 0))
        let insertionRange = NSRange(location: selectedLocation, length: max(context.selectionRange.length, 1))
        // Callers pass editable code-content ranges here, not full fenced ranges.
        // Otherwise EOF after a hidden closing fence inherits delimiter styling
        // and moves the outside blank-line caret to the code-block inset.
        if context.blockRanges.contains(where: { NSIntersectionRange($0, insertionRange).length > 0 }) {
            var attributes = codeBlockAttributes(font: context.baseFont, colorScheme: context.colorScheme)
            attributes[.foregroundColor] = context.baseColor
            return attributes
        }

        if context.inlineRanges.contains(where: { NSIntersectionRange($0, insertionRange).length > 0 }) {
            var attributes = inlineCodeAttributes(font: context.baseFont)
            attributes[.foregroundColor] = context.baseColor
            return attributes
        }

        return baseTypingAttributes(
            font: context.baseFont,
            foregroundColor: context.baseColor
        )
    }

    static func applyTextChips(
        to textStorage: NSTextStorage,
        chips: [AppTextEditorChip],
        fullRange: NSRange,
        compactDisplayResolver: (AppTextEditorChip) -> Bool
    ) {
        for chip in chips {
            let clampedRange = NSIntersectionRange(chip.range, fullRange)
            guard clampedRange.length > 0 else {
                continue
            }

            let compactDisplay = compactDisplayResolver(chip)

            textStorage.addAttributes(textChipAttributes(), range: clampedRange)

            if compactDisplay, chip.style == .fileMention {
                applyCompactFileMentionAttributes(
                    to: textStorage,
                    chipRange: clampedRange,
                    displayText: chip.displayText
                )
            }
            // Slash commands anchor to the line's leading edge, so their trailing side is
            // what touches the caret / inline hint / subsequent typed text. Add trailing
            // kerning there for visual breathing room. File mentions (and inline code)
            // are mid-line and typically sit between word-separating spaces — giving them
            // extra trailing padding would create asymmetric spacing ("room after, none
            // before"), so they stay tight.
            if chip.style == .slashCommand {
                applyTrailingKern(to: textStorage, chipRange: clampedRange, fullLength: fullRange.length)
            }
        }
    }

    // Extends the advance width of the chip's last character via `.kern` so the caret,
    // next typed character, and inline hint all align to the same x-position past the
    // chip. Relying on attribute-side kerning (instead of a post-hoc rect nudge) keeps
    // the three following-content types consistent — SwiftUI-side hint offsets would
    // not shift the caret or following text.
    static func applyTrailingKern(
        to textStorage: NSTextStorage,
        chipRange: NSRange,
        fullLength: Int
    ) {
        guard chipRange.length > 0 else {
            return
        }
        let lastCharacterRange = NSRange(
            location: chipRange.location + chipRange.length - 1,
            length: 1
        )
        guard NSMaxRange(lastCharacterRange) <= fullLength else {
            return
        }
        textStorage.addAttribute(.kern, value: appTextEditorChipTrailingKern, range: lastCharacterRange)
    }

    static func textChipAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(
                ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * 0.94,
                weight: .regular
            ),
            .foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor
        ]
    }

    // File-mention chips compact to an `@<basename>` label. The stored text may be
    // percent-encoded (so the mention regex can hold paths with spaces and other
    // terminators), which means the stored tail doesn't match the decoded display
    // label. Hide the entire stored chip text via a clear foreground and apply a
    // negative `.kern` to every stored char so their combined advances shrink to match
    // the decoded label's width — `.kern` adjusts each glyph's trailing advance and
    // `NSLayoutManager.enumerateEnclosingRects` reflects it, so the chip rect
    // collapses to the decoded label size. `AppKitTextView.drawCompactChipLabels`
    // then paints the decoded label over the shrunken chip rect.
    private static func applyCompactFileMentionAttributes(
        to textStorage: NSTextStorage,
        chipRange: NSRange,
        displayText: String
    ) {
        guard chipRange.length > 0 else {
            return
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.clear
        ]

        let decodedDisplayLength = (CanonicalPath.decodeStoredMentionPath(displayText) as NSString).length
        let storedLength = chipRange.length
        if storedLength > decodedDisplayLength,
           decodedDisplayLength > 0,
           let chipFont = textStorage.attribute(.font, at: chipRange.location, effectiveRange: nil) as? NSFont {
            let charAdvance = chipFont.maximumAdvancement.width
            let reductionPerChar = charAdvance * CGFloat(storedLength - decodedDisplayLength) / CGFloat(storedLength)
            if reductionPerChar > 0 {
                attributes[.kern] = -reductionPerChar
            }
        }

        textStorage.addAttributes(attributes, range: chipRange)
    }
}
