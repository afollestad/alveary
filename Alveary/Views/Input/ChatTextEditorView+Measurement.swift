@preconcurrency import AppKit

@MainActor
extension ChatTextEditorView {
    func scheduleHeightRecalculation() {
        guard !heightRecalculationScheduled else { return }
        // `configure` can run inside SwiftUI/AppKit update cycles; defer NSLayoutManager layout until they unwind.
        heightRecalculationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.heightRecalculationScheduled = false
            self.measureAndRefreshForCurrentLayout()
        }
    }

    func measureAndRefreshForCurrentLayout() {
        guard !isMeasuringLayout else { return }
        isMeasuringLayout = true
        defer { isMeasuringLayout = false }
        scrollView.layoutSubtreeIfNeeded()
        let availableWidth = availableTextWidth
        recalculateHeight()
        guard availableWidth > 0,
              abs(availableWidth - lastLaidOutTextWidth) > 0.5 else {
            return
        }
        lastLaidOutTextWidth = availableWidth
        refreshTextPresentationIfNeeded(force: true)
        textView.needsDisplay = true
    }

    var availableTextWidth: CGFloat { max(scrollView.contentSize.width, scrollView.bounds.width) }

    func recalculateHeight() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let availableWidth = availableTextWidth
        guard availableWidth > 0 else {
            return
        }

        if abs(textView.frame.width - availableWidth) > 0.5 {
            textView.frame.size.width = availableWidth
        }
        guard textView.updateTextContainerForCurrentBounds() else {
            return
        }
        guard textView.primeTextLayoutForDrawing() else {
            return
        }

        let lineHeight = layoutManager.defaultLineHeight(for: textView.baseTextFont)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let contentHeight = ceil(max(usedHeight, lineHeight) + (textView.textContainerInset.height * 2))
        if abs(textView.frame.height - max(contentHeight, scrollView.contentSize.height)) > 0.5 {
            textView.frame.size.height = max(contentHeight, scrollView.contentSize.height)
        }

        guard abs(lastMeasuredHeight - contentHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = contentHeight
        configuration.onMeasuredHeightChange(contentHeight)
    }

    func shouldCompactFileMentionChip(_ chip: AppTextEditorChip) -> Bool {
        let textLength = (textView.string as NSString).length
        let clampedRange = NSIntersectionRange(chip.range, NSRange(location: 0, length: textLength))
        guard clampedRange.length > 0, textView.textContainer?.containerSize.width ?? 0 > 0 else {
            return false
        }
        let storedText = (textView.string as NSString).substring(with: clampedRange)
        guard storedText != chip.displayText else {
            return false
        }
        guard compactFileMentionLabelFitsOnFirstLine(chip, clampedRange: clampedRange) else {
            return false
        }
        let selectedRange = textView.selectedRange()
        if selectedRange.length == 0 {
            return selectedRange.location < clampedRange.location || selectedRange.location >= NSMaxRange(clampedRange)
        }
        return NSIntersectionRange(selectedRange, clampedRange).length == 0
    }

    private func compactFileMentionLabelFitsOnFirstLine(
        _ chip: AppTextEditorChip,
        clampedRange: NSRange
    ) -> Bool {
        let chipRects = textView.textChipRects(for: clampedRange)
        guard let firstChipRect = chipRects.first else {
            return false
        }

        let decodedLabel = CanonicalPath.decodeStoredMentionPath(chip.displayText) as NSString
        let chipFont = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * 0.94,
            weight: .regular
        )
        let labelWidth = ceil(decodedLabel.size(withAttributes: [.font: chipFont]).width)
        let availableLineWidth = max(textView.bounds.maxX - textView.textContainerInset.width - firstChipRect.minX, 0)
        return labelWidth <= availableLineWidth
    }
}
