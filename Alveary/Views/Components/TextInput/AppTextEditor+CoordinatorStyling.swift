@preconcurrency import AppKit

@MainActor
extension AppKitTextEditorCoordinator {
    func handleLayoutChange() {
        guard let textView,
              let scrollView else {
            return
        }

        let availableWidth = scrollView.contentSize.width
        recalculateHeight()

        guard availableWidth > 0,
              abs(availableWidth - lastLaidOutTextWidth) > 0.5 else {
            return
        }

        lastLaidOutTextWidth = availableWidth
        applyTextHighlights()
        textView.needsDisplay = true
    }

    func syncTextChipPresentation(for textView: AppKitTextView) {
        textView.textChips = parent.textChips?(textView.string) ?? []
    }

    func refreshTypingAttributes() {
        guard let textView else {
            return
        }

        let baseFont = textView.baseTextFont
        let baseColor = NSColor.labelColor
        let blockRanges = parent.codeBlockRanges?(textView.string) ?? []
        let inlineRanges = parent.inlineCodeRanges?(textView.string) ?? []

        updateTypingAttributes(
            for: textView,
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
        )
    }

    func applyTextHighlights() {
        guard let textView,
              let textStorage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = textView.baseTextFont
        let baseColor = NSColor.labelColor
        let blockRanges = parent.codeBlockRanges?(textView.string) ?? []
        let inlineRanges = parent.inlineCodeRanges?(textView.string) ?? []
        let inlineDelimiterRanges = parent.inlineCodeDelimiterRanges?(textView.string) ?? []
        guard fullRange.length > 0 else {
            textView.typingAttributes = AppTextEditorCodeBlockStyling.baseTypingAttributes(
                font: baseFont,
                foregroundColor: baseColor
            )
            textView.primeTextLayoutForDrawing()
            return
        }

        let highlightRanges = parent.textHighlightRanges?(textView.string) ?? []
        let compactDisplayChips = compactDisplayChips(for: textView)

        textView.markTextLayoutNeedsPriming()
        textStorage.beginEditing()
        applyStyling(
            to: textStorage,
            fullRange: fullRange,
            ranges: .init(
                highlightRanges: highlightRanges,
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                inlineDelimiterRanges: inlineDelimiterRanges
            ),
            baseFont: baseFont,
            baseColor: baseColor
        )
        applyTextChips(to: textStorage, textView: textView, fullRange: fullRange, compactDisplayChips: compactDisplayChips)
        textStorage.endEditing()
        textView.primeTextLayoutForDrawing()
        updateTypingAttributes(
            for: textView,
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
        )
    }

    private struct HighlightRanges {
        let highlightRanges: [NSRange]
        let blockRanges: [NSRange]
        let inlineRanges: [NSRange]
        let inlineDelimiterRanges: [NSRange]
    }

    private func applyStyling(
        to textStorage: NSTextStorage,
        fullRange: NSRange,
        ranges: HighlightRanges,
        baseFont: NSFont,
        baseColor: NSColor
    ) {
        AppTextEditorCodeBlockStyling.apply(
            to: textStorage,
            context: .init(
                fullRange: fullRange,
                highlightRanges: ranges.highlightRanges,
                blockRanges: ranges.blockRanges,
                inlineRanges: ranges.inlineRanges,
                inlineDelimiterRanges: ranges.inlineDelimiterRanges,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: parent.colorScheme
            )
        )
    }

    private func applyTextChips(
        to textStorage: NSTextStorage,
        textView: AppKitTextView,
        fullRange: NSRange,
        compactDisplayChips: [AppTextEditorChip]
    ) {
        AppTextEditorCodeBlockStyling.applyTextChips(
            to: textStorage,
            chips: textView.textChips,
            fullRange: fullRange,
            compactDisplayResolver: { compactDisplayChips.contains($0) }
        )
    }

    private func updateTypingAttributes(
        for textView: AppKitTextView,
        blockRanges: [NSRange],
        inlineRanges: [NSRange],
        baseFont: NSFont,
        baseColor: NSColor
    ) {
        textView.typingAttributes = AppTextEditorCodeBlockStyling.typingAttributes(
            for: .init(
                selectionRange: textView.selectedRange(),
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                textUTF16Count: parent.text.utf16.count,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: parent.colorScheme
            )
        )
    }

    private func compactDisplayChips(for textView: AppKitTextView) -> [AppTextEditorChip] {
        textView.textChips.filter { chip in
            textView.textChipDisplayMode(for: chip) == .compactLabel(chip.displayText)
        }
    }
}
