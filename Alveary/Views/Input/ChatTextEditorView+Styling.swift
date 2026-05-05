@preconcurrency import AppKit
import SwiftUI

/// Text presentation for `ChatTextEditorView`.
///
/// Keep this path idempotent. AppKit text storage and typing-attribute updates
/// can synchronously ask `NSLayoutManager` and fallback-font code to inspect the
/// editor while SwiftUI is still driving representable layout.
@MainActor
extension ChatTextEditorView {
    func syncInlineCodePresentation() {
        textView.inlineCodeBackgroundRanges = configuration.inlineCodeBackgroundRanges(textView.string)
        textView.inlineCodeBackgroundColor = AppMarkdownCodeBlockPalette.composerChipFillNSColor
    }

    func syncTextChipPresentation() {
        textView.textChips = configuration.textChips(textView.string)
    }

    func refreshTextPresentationIfNeeded(force: Bool = false) {
        let fingerprint = ChatTextEditorStylingFingerprint(
            text: textView.string,
            selectedRange: textView.selectedRange(),
            colorScheme: configuration.colorScheme,
            textHighlightRanges: configuration.textHighlightRanges(textView.string),
            textChips: configuration.textChips(textView.string),
            codeBlockRanges: configuration.codeBlockRanges(textView.string),
            inlineCodeBackgroundRanges: configuration.inlineCodeBackgroundRanges(textView.string),
            inlineCodeRanges: configuration.inlineCodeRanges(textView.string),
            inlineCodeDelimiterRanges: configuration.inlineCodeDelimiterRanges(textView.string),
            baseFontDescriptor: ChatTextEditorFontDescriptor(textView.baseTextFont)
        )
        guard force || fingerprint != lastAppliedStylingFingerprint else {
            return
        }
        lastAppliedStylingFingerprint = fingerprint
        #if DEBUG
        presentationApplyCountForTesting += 1
        #endif
        syncInlineCodePresentation()
        syncTextChipPresentation()
        applyTextHighlights()
    }

    func applyTextHighlights() {
        guard let textStorage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = textView.baseTextFont
        let baseColor = NSColor.labelColor
        let blockRanges = configuration.codeBlockRanges(textView.string)
        let inlineRanges = configuration.inlineCodeRanges(textView.string)
        let inlineDelimiterRanges = configuration.inlineCodeDelimiterRanges(textView.string)
        let compactDisplayChips = compactDisplayChips()
        guard fullRange.length > 0 else {
            updateTypingAttributes(
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                baseFont: baseFont,
                baseColor: baseColor
            )
            textView.primeTextLayoutForDrawing()
            return
        }

        textView.markTextLayoutNeedsPriming()
        applyTextStorageHighlights(.init(
            textStorage: textStorage,
            fullRange: fullRange,
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            inlineDelimiterRanges: inlineDelimiterRanges,
            compactDisplayChips: compactDisplayChips,
            baseFont: baseFont,
            baseColor: baseColor
        ))
        textView.primeTextLayoutForDrawing()
        updateTypingAttributes(
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
        )
    }

    func applyTextStorageHighlights(_ context: ChatTextEditorHighlightContext) {
        context.textStorage.beginEditing()
        AppTextEditorCodeBlockStyling.apply(
            to: context.textStorage,
            context: .init(
                fullRange: context.fullRange,
                highlightRanges: configuration.textHighlightRanges(textView.string),
                blockRanges: context.blockRanges,
                inlineRanges: context.inlineRanges,
                inlineDelimiterRanges: context.inlineDelimiterRanges,
                baseFont: context.baseFont,
                baseColor: context.baseColor,
                colorScheme: configuration.colorScheme
            )
        )
        AppTextEditorCodeBlockStyling.applyTextChips(
            to: context.textStorage,
            chips: textView.textChips,
            fullRange: context.fullRange,
            compactDisplayResolver: { chip in
                context.compactDisplayChips.contains(chip)
            }
        )
        context.textStorage.endEditing()
    }

    func refreshTypingAttributes() {
        updateTypingAttributes(
            blockRanges: configuration.codeBlockRanges(textView.string),
            inlineRanges: configuration.inlineCodeRanges(textView.string),
            baseFont: textView.baseTextFont,
            baseColor: .labelColor
        )
    }

    func updateTypingAttributes(
        blockRanges: [NSRange],
        inlineRanges: [NSRange],
        baseFont: NSFont,
        baseColor: NSColor
    ) {
        let fingerprint = ChatTextEditorTypingFingerprint(
            selectedRange: textView.selectedRange(),
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            textUTF16Count: textView.string.utf16.count,
            baseFontDescriptor: ChatTextEditorFontDescriptor(baseFont),
            baseColorDescription: baseColor.description,
            colorScheme: configuration.colorScheme
        )
        guard fingerprint != lastAppliedTypingFingerprint else {
            return
        }
        lastAppliedTypingFingerprint = fingerprint
        #if DEBUG
        typingAttrsApplyCountForTesting += 1
        #endif
        // Resetting typing attributes can synchronously ask AppKit to inspect
        // fallback fonts while SwiftUI is driving layout. Keep this idempotent.
        textView.typingAttributes = AppTextEditorCodeBlockStyling.typingAttributes(
            for: .init(
                selectionRange: textView.selectedRange(),
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                textUTF16Count: textView.string.utf16.count,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: configuration.colorScheme
            )
        )
    }

    func scheduleSelectionRestyle() {
        guard !selectionRestyleScheduled else {
            return
        }

        selectionRestyleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.selectionRestyleScheduled = false
            self.refreshTextPresentationIfNeeded(force: true)
            self.textView.needsDisplay = true
        }
    }

    func compactDisplayChips() -> [AppTextEditorChip] {
        // `textChipDisplayMode` asks NSLayoutManager for glyph rects, so compute
        // it before `NSTextStorage.beginEditing()`. AppKit raises if glyph layout
        // is forced while attributes are being mutated.
        textView.textChips.filter { chip in
            if chip.style == .fileMention {
                return shouldCompactFileMentionChip(chip)
            }
            return textView.textChipDisplayMode(for: chip) == .compactLabel(chip.displayText)
        }
    }
}

/// Captures every input that changes attributed text storage, chip display, or
/// code highlighting so repeated SwiftUI/AppKit configuration passes can no-op.
struct ChatTextEditorStylingFingerprint: Equatable {
    let text: String
    let selectedRange: NSRange
    let colorScheme: ColorScheme
    let textHighlightRanges: [NSRange]
    let textChips: [AppTextEditorChip]
    let codeBlockRanges: [NSRange]
    let inlineCodeBackgroundRanges: [NSRange]
    let inlineCodeRanges: [NSRange]
    let inlineCodeDelimiterRanges: [NSRange]
    let baseFontDescriptor: ChatTextEditorFontDescriptor
}

/// Captures every input that changes `NSTextView.typingAttributes`; resetting
/// those attributes is observable to AppKit and should not happen on every pass.
struct ChatTextEditorTypingFingerprint: Equatable {
    let selectedRange: NSRange
    let blockRanges: [NSRange]
    let inlineRanges: [NSRange]
    let textUTF16Count: Int
    let baseFontDescriptor: ChatTextEditorFontDescriptor
    let baseColorDescription: String
    let colorScheme: ColorScheme
}

struct ChatTextEditorHighlightContext {
    let textStorage: NSTextStorage
    let fullRange: NSRange
    let blockRanges: [NSRange]
    let inlineRanges: [NSRange]
    let inlineDelimiterRanges: [NSRange]
    let compactDisplayChips: [AppTextEditorChip]
    let baseFont: NSFont
    let baseColor: NSColor
}

struct ChatTextEditorFontDescriptor: Equatable {
    let fontName: String
    let pointSize: CGFloat

    init(_ font: NSFont) {
        fontName = font.fontName
        pointSize = font.pointSize
    }
}
