@preconcurrency import AppKit

extension AppKitTextView {
    func drawInlineCodeBackgrounds(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout(),
              !inlineCodeBackgroundRanges.isEmpty else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let drawingOffset = textContainerOrigin
        let cornerRadius: CGFloat = 4
        let horizontalInset: CGFloat = 3
        let verticalInset: CGFloat = 1

        for characterRange in inlineCodeBackgroundRanges {
            let clampedRange = NSIntersectionRange(characterRange, NSRange(location: 0, length: (string as NSString).length))
            guard clampedRange.length > 0 else {
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                continue
            }

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { enclosingRect, _ in
                let backgroundRect = NSRect(
                    x: enclosingRect.minX + drawingOffset.x - horizontalInset,
                    y: enclosingRect.minY + drawingOffset.y - verticalInset,
                    width: enclosingRect.width + (horizontalInset * 2),
                    height: enclosingRect.height + (verticalInset * 2)
                ).integral

                guard backgroundRect.intersects(dirtyRect) else {
                    return
                }

                self.inlineCodeBackgroundColor.setFill()
                NSBezierPath(
                    roundedRect: backgroundRect,
                    xRadius: cornerRadius,
                    yRadius: cornerRadius
                ).fill()
            }
        }
    }

    func textChipDisplayMode(for chip: AppTextEditorChip) -> AppTextEditorChipDisplayMode {
        let textLength = (string as NSString).length
        let clampedRange = NSIntersectionRange(chip.range, NSRange(location: 0, length: textLength))
        guard clampedRange.length > 0 else {
            return .fullText
        }

        let fullText = (string as NSString).substring(with: clampedRange)
        guard fullText != chip.displayText,
              !selectionIntersectsChip(clampedRange),
              textChipRects(for: clampedRange).count == 1 else {
            return .fullText
        }

        return .compactLabel(chip.displayText)
    }

    func drawTextChipBackgrounds(in dirtyRect: NSRect) {
        let cornerRadius: CGFloat = 4
        AppMarkdownCodeBlockPalette.composerChipFillNSColor.setFill()

        for resolvedChip in resolvedTextChips() {
            for rect in resolvedChip.rects where rect.intersects(dirtyRect) {
                NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }
        }
    }

    func textChipRects(for characterRange: NSRange) -> [NSRect] {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout() else {
            return []
        }

        let textLength = (string as NSString).length
        let clampedRange = NSIntersectionRange(characterRange, NSRange(location: 0, length: textLength))
        guard clampedRange.length > 0 else {
            return []
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return []
        }

        let drawingOffset = textContainerOrigin
        let desiredInset: CGFloat = 3
        // Match `drawInlineCodeBackgrounds`'s `verticalInset` so `/command` and
        // `@mention` chips render at the same apparent height as inline-code chips
        // — a previous `2` was 2pt taller overall and read as a visual mismatch.
        let verticalInset: CGFloat = 1
        let leftInset = chipLeadingInset(
            for: clampedRange,
            layoutManager: layoutManager,
            textContainer: textContainer,
            desiredInset: desiredInset
        )
        let rightInset = chipTrailingInset(
            for: clampedRange,
            layoutManager: layoutManager,
            textContainer: textContainer,
            desiredInset: desiredInset
        )
        var rects: [NSRect] = []

        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { enclosingRect, _ in
            rects.append(
                NSRect(
                    x: enclosingRect.minX + drawingOffset.x - leftInset,
                    y: enclosingRect.minY + drawingOffset.y - verticalInset,
                    width: enclosingRect.width + leftInset + rightInset,
                    height: enclosingRect.height + (verticalInset * 2)
                ).integral
            )
        }

        return rects
    }

    func chipLeadingInset(
        for _: NSRange,
        layoutManager _: NSLayoutManager,
        textContainer _: NSTextContainer,
        desiredInset _: CGFloat
    ) -> CGFloat {
        0
    }

    func chipTrailingInset(
        for _: NSRange,
        layoutManager _: NSLayoutManager,
        textContainer _: NSTextContainer,
        desiredInset _: CGFloat
    ) -> CGFloat {
        0
    }

    private func resolvedTextChips() -> [ResolvedTextChip] {
        textChips.compactMap { chip in
            let rects = textChipRects(for: chip.range)
            guard !rects.isEmpty else {
                return nil
            }

            return ResolvedTextChip(chip: chip, rects: rects)
        }
    }

    private func selectionIntersectsChip(_ chipRange: NSRange) -> Bool {
        let selectionRange = selectedRange()

        if selectionRange.length == 0 {
            return selectionRange.location >= chipRange.location && selectionRange.location < NSMaxRange(chipRange)
        }

        return NSIntersectionRange(selectionRange, chipRange).length > 0
    }
}

private struct ResolvedTextChip {
    let chip: AppTextEditorChip
    let rects: [NSRect]
}
