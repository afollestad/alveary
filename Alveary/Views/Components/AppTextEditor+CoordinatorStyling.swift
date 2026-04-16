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
            return
        }

        let highlightRanges = parent.textHighlightRanges?(textView.string) ?? []
        let compactDisplayChips = compactDisplayChips(for: textView)

        textStorage.beginEditing()
        AppTextEditorCodeBlockStyling.apply(
            to: textStorage,
            context: .init(
                fullRange: fullRange,
                highlightRanges: highlightRanges,
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                inlineDelimiterRanges: inlineDelimiterRanges,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: parent.colorScheme
            )
        )
        AppTextEditorCodeBlockStyling.applyTextChips(
            to: textStorage,
            chips: textView.textChips,
            fullRange: fullRange,
            colorScheme: parent.colorScheme,
            compactDisplayResolver: { chip in
                compactDisplayChips.contains(chip)
            }
        )
        textStorage.endEditing()
        updateTypingAttributes(
            for: textView,
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
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
