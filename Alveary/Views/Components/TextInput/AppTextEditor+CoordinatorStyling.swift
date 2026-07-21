@preconcurrency import AppKit
import SwiftUI

struct AppKitTextPresentationConfiguration: Equatable {
    let highlightRanges: [NSRange]
    let textChips: [AppTextEditorChip]
    let blockRanges: [NSRange]
    let inlineCodeBackgroundRanges: [NSRange]
    let inlineRanges: [NSRange]
    let inlineDelimiterRanges: [NSRange]
    let baseFont: NSFont
    let baseColor: NSColor
    let inlineCodeBackgroundColor: NSColor
    let accentColor: NSColor
    let colorScheme: ColorScheme
}

@MainActor
extension AppKitTextEditorCoordinator {
    @discardableResult
    func applyViewConfiguration(to textView: AppKitTextView, from parent: AppKitTextEditorView) -> Bool {
        let showsDisabledCursor = parent.isDisabled && parent.showsDisabledCursor
        assignIfChanged(\.baseTextFont, on: textView, value: .preferredFont(forTextStyle: .body))
        assignIfChanged(\.isEditable, on: textView, value: !parent.isDisabled)
        assignIfChanged(\.isSelectable, on: textView, value: !showsDisabledCursor)
        assignIfChanged(\.showsDisabledCursor, on: textView, value: showsDisabledCursor)
        if let scrollView {
            assignIfChanged(\.showsDisabledCursor, on: scrollView, value: showsDisabledCursor)
        }
        if let clipView = scrollView?.contentView as? AppKitTextEditorClipView {
            assignIfChanged(\.showsDisabledCursor, on: clipView, value: showsDisabledCursor)
        }
        if let containerView {
            assignIfChanged(\.showsDisabledCursor, on: containerView, value: showsDisabledCursor)
        }
        assignIfChanged(\.textColor, on: textView, value: .labelColor)
        assignIfChanged(\.placeholder, on: textView, value: parent.placeholder ?? "")
        assignIfChanged(\.inlineHint, on: textView, value: parent.inlineHint)
        assignIfChanged(\.enablesCodeBlockEditing, on: textView, value: parent.codeBlockRanges != nil)
        assignIfChanged(\.disablesAppKitDragDestination, on: textView, value: parent.disablesAppKitDragDestination)

        let inset = NSSize(width: parent.horizontalPadding, height: parent.verticalPadding)
        guard textView.textContainerInset != inset else {
            return false
        }

        textView.textContainerInset = inset
        textView.updateTextContainerForCurrentBounds()
        return true
    }

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
        if !textView.textChips.isEmpty {
            refreshTextPresentationIfNeeded(for: textView, parent: parent, force: true)
        }
        textView.needsDisplay = true
    }

    @discardableResult
    func refreshTextPresentationIfNeeded(
        for textView: AppKitTextView,
        parent: AppKitTextEditorView,
        force: Bool = false
    ) -> Bool {
        let configuration = textPresentationConfiguration(for: textView, parent: parent)
        guard force || configuration != appliedTextPresentationConfiguration else {
            return false
        }

        appliedTextPresentationConfiguration = configuration
        textView.updateTextContainerForCurrentBounds()
        if textView.textChips != configuration.textChips {
            textView.textChips = configuration.textChips
        }
        if textView.inlineCodeBackgroundRanges != configuration.inlineCodeBackgroundRanges {
            textView.inlineCodeBackgroundRanges = configuration.inlineCodeBackgroundRanges
        }
        if textView.inlineCodeBackgroundColor != configuration.inlineCodeBackgroundColor {
            textView.inlineCodeBackgroundColor = configuration.inlineCodeBackgroundColor
        }
        applyTextHighlights(configuration: configuration)
        textView.refreshInlineHintView()
        textView.needsDisplay = true
        return true
    }

    func refreshTypingAttributes() {
        guard let textView else {
            return
        }

        let baseFont = textView.baseTextFont
        let baseColor = NSColor.labelColor
        let blockRanges = parent.codeBlockRanges?(textView.string) ?? []
        let blockContentRanges = AppMarkdownCodeBlockParser
            .blockCodeRanges(in: textView.string, matching: blockRanges)
            .map(\.contentRange)
        let inlineRanges = parent.inlineCodeRanges?(textView.string) ?? []

        updateTypingAttributes(
            for: textView,
            blockRanges: blockContentRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
        )
    }

    func applyTextHighlights() {
        guard let textView else {
            return
        }

        refreshTextPresentationIfNeeded(for: textView, parent: parent, force: true)
    }

    private func applyTextHighlights(configuration: AppKitTextPresentationConfiguration) {
        guard let textView,
              let textStorage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let blockContentRanges = AppMarkdownCodeBlockParser
            .blockCodeRanges(in: textView.string, matching: configuration.blockRanges)
            .map(\.contentRange)
        textView.codeBlockBackgroundRanges = blockContentRanges
        guard fullRange.length > 0 else {
            textView.typingAttributes = AppTextEditorCodeBlockStyling.baseTypingAttributes(
                font: configuration.baseFont,
                foregroundColor: configuration.baseColor
            )
            textView.primeTextLayoutForDrawing()
            return
        }

        let compactDisplayChips = compactDisplayChips(for: textView)

        textView.markTextLayoutNeedsPriming()
        textStorage.beginEditing()
        applyStyling(
            to: textStorage,
            fullRange: fullRange,
            ranges: .init(
                highlightRanges: configuration.highlightRanges,
                blockRanges: configuration.blockRanges,
                inlineRanges: configuration.inlineRanges,
                inlineDelimiterRanges: configuration.inlineDelimiterRanges
            ),
            baseFont: configuration.baseFont,
            baseColor: configuration.baseColor
        )
        applyTextChips(to: textStorage, textView: textView, fullRange: fullRange, compactDisplayChips: compactDisplayChips)
        textStorage.endEditing()
        textView.primeTextLayoutForDrawing()
        updateTypingAttributes(
            for: textView,
            blockRanges: blockContentRanges,
            inlineRanges: configuration.inlineRanges,
            baseFont: configuration.baseFont,
            baseColor: configuration.baseColor
        )
    }

    private func textPresentationConfiguration(
        for textView: AppKitTextView,
        parent: AppKitTextEditorView
    ) -> AppKitTextPresentationConfiguration {
        let text = textView.string
        return AppKitTextPresentationConfiguration(
            highlightRanges: parent.textHighlightRanges?(text) ?? [],
            textChips: parent.textChips?(text) ?? [],
            blockRanges: parent.codeBlockRanges?(text) ?? [],
            inlineCodeBackgroundRanges: parent.inlineCodeBackgroundRanges?(text) ?? [],
            inlineRanges: parent.inlineCodeRanges?(text) ?? [],
            inlineDelimiterRanges: parent.inlineCodeDelimiterRanges?(text) ?? [],
            baseFont: textView.baseTextFont,
            baseColor: .labelColor,
            inlineCodeBackgroundColor: AppMarkdownCodeBlockPalette.composerChipFillNSColor,
            accentColor: .controlAccentColor,
            colorScheme: parent.colorScheme
        )
    }

    private func assignIfChanged<Root: AnyObject, Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Root, Value>,
        on root: Root,
        value: Value
    ) {
        guard root[keyPath: keyPath] != value else {
            return
        }
        root[keyPath: keyPath] = value
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
