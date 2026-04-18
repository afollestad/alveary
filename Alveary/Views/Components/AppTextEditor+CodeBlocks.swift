@preconcurrency import AppKit
import SwiftUI

enum AppTextEditorCodeBlockStyling {
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

        for range in context.inlineRanges {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0,
                  !context.blockRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }) else {
                continue
            }

            textStorage.addAttributes(
                inlineCodeAttributes(font: context.baseFont),
                range: clampedRange
            )
        }

        for range in context.inlineDelimiterRanges {
            let clampedRange = NSIntersectionRange(range, context.fullRange)
            guard clampedRange.length > 0,
                  !context.blockRanges.contains(where: { NSIntersectionRange($0, clampedRange).length > 0 }) else {
                continue
            }

            textStorage.addAttributes(
                inlineCodeDelimiterAttributes(font: context.baseFont),
                range: clampedRange
            )
        }

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
        paragraphStyle.firstLineHeadIndent = 6
        paragraphStyle.headIndent = 6
        paragraphStyle.tailIndent = -6
        paragraphStyle.paragraphSpacingBefore = 2
        paragraphStyle.paragraphSpacing = 2

        return [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular),
            .paragraphStyle: paragraphStyle,
            .backgroundColor: AppMarkdownCodeBlockPalette.fillNSColor(for: colorScheme)
        ]
    }

    static func inlineCodeAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.94, weight: .regular),
            .foregroundColor: AppMarkdownCodeBlockPalette.inlineForegroundNSColor
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

            textStorage.addAttributes(
                textChipAttributes(style: chip.style, compactDisplay: compactDisplay),
                range: clampedRange
            )

            if compactDisplay, chip.style == .fileMention {
                applyCompactFileMentionAttributes(
                    to: textStorage,
                    chipRange: clampedRange,
                    displayText: chip.displayText
                )
            }
        }
    }

    static func textChipAttributes(
        style: AppTextEditorChipStyle,
        compactDisplay: Bool
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(
                ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * 0.94,
                weight: .regular
            ),
            .foregroundColor: compactDisplay && style != .fileMention
                ? NSColor.clear
                : AppMarkdownCodeBlockPalette.inlineForegroundNSColor
        ]
    }

    private static func applyCompactFileMentionAttributes(
        to textStorage: NSTextStorage,
        chipRange: NSRange,
        displayText: String
    ) {
        let fullText = (textStorage.string as NSString).substring(with: chipRange)
        let fullLength = (fullText as NSString).length
        let displayLength = (displayText as NSString).length
        let hiddenPrefixLength = fullLength - displayLength

        guard fullLength > 1,
              hiddenPrefixLength > 0 else {
            return
        }

        let hiddenPrefixRange = NSRange(location: chipRange.location + 1, length: hiddenPrefixLength)
        let visibleSuffixRange = NSRange(
            location: hiddenPrefixRange.location + hiddenPrefixLength,
            length: chipRange.length - hiddenPrefixLength - 1
        )
        let visibleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: AppMarkdownCodeBlockPalette.inlineForegroundNSColor
        ]
        let baseFont = (textStorage.attribute(.font, at: chipRange.location, effectiveRange: nil) as? NSFont) ??
            .preferredFont(forTextStyle: .body)

        textStorage.addAttributes(hiddenFileMentionPrefixAttributes(baseFont: baseFont), range: hiddenPrefixRange)
        textStorage.addAttributes(visibleAttributes, range: NSRange(location: chipRange.location, length: 1))
        if visibleSuffixRange.length > 0 {
            textStorage.addAttributes(visibleAttributes, range: visibleSuffixRange)
        }
    }

    private static func hiddenFileMentionPrefixAttributes(baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: max(baseFont.pointSize * 0.01, 0.1)),
            .foregroundColor: NSColor.clear
        ]
    }
}
