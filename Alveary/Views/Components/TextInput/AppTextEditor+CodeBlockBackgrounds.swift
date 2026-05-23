@preconcurrency import AppKit

/// Draws fenced-code-block chrome for `AppKitTextView`.
///
/// The backing text still contains the markdown fences. Those delimiter lines are
/// styled as hidden text in `AppTextEditorCodeBlockStyling`, while this extension
/// draws the visible rounded background around the editable code content.
extension AppKitTextView {
    func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        guard !codeBlockBackgroundRanges.isEmpty else {
            return
        }

        let fillColor = AppMarkdownCodeBlockPalette.fillNSColor(for: effectiveAppearance)
        let borderColor = AppMarkdownCodeBlockPalette.borderNSColor(for: effectiveAppearance)
        let cornerRadius = AppKitMarkdownMetrics.codeCornerRadius

        for characterRange in codeBlockBackgroundRanges {
            for rect in codeBlockBackgroundRects(for: characterRange) where rect.intersects(dirtyRect) {
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                fillColor.setFill()
                path.fill()

                borderColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    func codeBlockBackgroundRects(for characterRange: NSRange) -> [NSRect] {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout() else {
            return []
        }

        let textLength = (string as NSString).length
        let clampedRange = NSIntersectionRange(characterRange, NSRange(location: 0, length: textLength))
        if clampedRange.length == 0 {
            return emptyCodeBlockBackgroundRects(at: min(max(characterRange.location, 0), textLength))
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return []
        }

        let drawingOffset = textContainerOrigin
        guard var resolvedRect = rawCodeBlockBackgroundRect(
            for: glyphRange,
            characterRange: characterRange,
            layoutManager: layoutManager,
            drawingOffset: drawingOffset
        ) else {
            return []
        }
        resolvedRect.rect.size.width = codeBlockBackgroundWidth(forLineMaxX: resolvedRect.widestLineMaxX)

        let adjustedRect = codeBlockBackgroundRectWithOuterGaps(
            resolvedRect.rect,
            for: characterRange,
            layoutManager: layoutManager,
            drawingOffset: drawingOffset
        )
        guard adjustedRect.height > 0 else {
            return []
        }

        return [adjustedRect.integral.insetBy(dx: 0.5, dy: 0.5)]
    }

    private func emptyCodeBlockBackgroundRects(at location: Int) -> [NSRect] {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout() else {
            return []
        }

        layoutManager.ensureLayout(for: textContainer)
        let drawingOffset = textContainerOrigin
        let lineFragmentRect: NSRect

        if location >= (string as NSString).length,
           !layoutManager.extraLineFragmentUsedRect.isEmpty {
            lineFragmentRect = layoutManager.extraLineFragmentRect
        } else {
            let characterIndex = max(min(location, (string as NSString).length - 1), 0)
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            guard glyphIndex < layoutManager.numberOfGlyphs else {
                return []
            }
            lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }

        let horizontalMargin = codeBlockHorizontalMargin
        let verticalInset = AppTextEditorCodeBlockStyling.codeBlockVerticalPadding
        let editableLineHeight = ceil(layoutManager.defaultLineHeight(for: baseTextFont))
        let backgroundHeight = max(lineFragmentRect.height, editableLineHeight)
        let backgroundRect = codeBlockBackgroundRectWithOuterGaps(
            NSRect(
                x: bounds.minX + horizontalMargin,
                y: lineFragmentRect.minY + drawingOffset.y - verticalInset,
                width: codeBlockBackgroundWidth(forLineMaxX: 0),
                height: backgroundHeight + (verticalInset * 2)
            ),
            for: NSRange(location: location, length: 0),
            layoutManager: layoutManager,
            drawingOffset: drawingOffset
        )
        guard backgroundRect.height > 0 else {
            return []
        }

        return [backgroundRect.integral.insetBy(dx: 0.5, dy: 0.5)]
    }

    func emptyCodeBlockInsertionRange(at point: NSPoint) -> NSRange? {
        for range in codeBlockBackgroundRanges where range.length == 0 {
            if codeBlockBackgroundRects(for: range).contains(where: { $0.contains(point) }) {
                return NSRange(location: range.location, length: 0)
            }
        }

        for blockRange in AppMarkdownCodeBlockParser.blockCodeRanges(in: string)
            where blockRange.contentRange.length == 0 &&
            codeBlockBackgroundRanges.contains(blockRange.contentRange) {
            if codeBlockBackgroundRects(for: blockRange.contentRange).contains(where: { $0.contains(point) }) {
                return NSRange(location: blockRange.contentRange.location, length: 0)
            }
        }

        return nil
    }

    func drawTextExcludingHiddenCodeBlockDelimiters(in dirtyRect: NSRect) {
        guard let exclusionPath = hiddenCodeBlockDelimiterExclusionPath(in: dirtyRect) else {
            super.draw(dirtyRect)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        exclusionPath.addClip()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    func codeBlockVisualContentHeight() -> CGFloat? {
        let maxBlockY = codeBlockBackgroundRanges
            .flatMap { codeBlockBackgroundRects(for: $0) }
            .map(\.maxY)
            .max()
        guard let maxBlockY else {
            return nil
        }

        return ceil(maxBlockY + textContainerInset.height)
    }

    func codeBlockPreferredContentHeight() -> CGFloat? {
        guard let visualHeight = codeBlockVisualContentHeight() else {
            return nil
        }

        // The block's own bottom gap is separate from the composer inset. The
        // caller still adds the text view inset so the chrome does not hug the
        // parent border.
        return ceil(max(
            visualHeight + AppTextEditorCodeBlockStyling.codeBlockComposerBreathingRoom,
            trailingClosedCodeBlockOutsideLineHeight() ?? 0
        ))
    }

    private var codeBlockHorizontalMargin: CGFloat {
        textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
    }

    private func rawCodeBlockBackgroundRect(
        for glyphRange: NSRange,
        characterRange: NSRange,
        layoutManager: NSLayoutManager,
        drawingOffset: NSPoint
    ) -> (rect: NSRect, widestLineMaxX: CGFloat)? {
        let horizontalMargin = codeBlockHorizontalMargin
        let verticalInset = AppTextEditorCodeBlockStyling.codeBlockVerticalPadding
        var backgroundRect: NSRect?
        var widestLineMaxX: CGFloat = 0

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, usedRect, _, _, _ in
            widestLineMaxX = max(widestLineMaxX, usedRect.maxX)
            let lineRect = self.codeLineBackgroundRect(
                for: lineFragmentRect,
                horizontalMargin: horizontalMargin,
                drawingOffset: drawingOffset,
                verticalInset: verticalInset
            )
            backgroundRect = backgroundRect.map { $0.union(lineRect) } ?? lineRect
        }
        if let trailingLineRect = trailingEditableCodeLineFragmentRect(after: characterRange, layoutManager: layoutManager) {
            let lineRect = codeLineBackgroundRect(
                for: trailingLineRect,
                horizontalMargin: horizontalMargin,
                drawingOffset: drawingOffset,
                verticalInset: verticalInset
            )
            backgroundRect = backgroundRect.map { $0.union(lineRect) } ?? lineRect
        }

        guard let backgroundRect else {
            return nil
        }
        return (backgroundRect, widestLineMaxX)
    }

    private func codeBlockBackgroundWidth(forLineMaxX lineMaxX: CGFloat) -> CGFloat {
        let maximumWidth = max(bounds.width - (codeBlockHorizontalMargin * 2), 0)
        let minimumWidth = max(ceil(baseTextFont.pointSize * 12), 144)
        let naturalWidth = max(lineMaxX + AppTextEditorCodeBlockStyling.codeBlockHorizontalPadding, minimumWidth)
        return min(naturalWidth, maximumWidth)
    }

    private func trailingClosedCodeBlockOutsideLineHeight() -> CGFloat? {
        guard let layoutManager,
              prepareForSafeTextLayout() else {
            return nil
        }

        let textLength = (string as NSString).length
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: baseTextFont))
        return AppMarkdownCodeBlockParser.blockCodeRanges(in: string)
            .filter { codeBlockBackgroundRanges.contains($0.contentRange) }
            .compactMap { blockRange -> CGFloat? in
                guard let closingDelimiter = blockRange.delimiterRanges.dropFirst().first,
                      NSMaxRange(closingDelimiter) == textLength,
                      let backgroundRect = codeBlockBackgroundRects(for: blockRange.contentRange).first else {
                    return nil
                }

                return backgroundRect.maxY +
                    AppTextEditorCodeBlockStyling.codeBlockOuterGap +
                    lineHeight +
                    textContainerInset.height
            }
            .max()
    }

    private func codeLineBackgroundRect(
        for lineFragmentRect: NSRect,
        horizontalMargin: CGFloat,
        drawingOffset: NSPoint,
        verticalInset: CGFloat
    ) -> NSRect {
        NSRect(
            x: bounds.minX + horizontalMargin,
            y: lineFragmentRect.minY + drawingOffset.y - verticalInset,
            width: 0,
            height: lineFragmentRect.height + (verticalInset * 2)
        )
    }

    func hiddenCodeBlockDelimiterRects() -> [NSRect] {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout() else {
            return []
        }

        let textLength = (string as NSString).length
        guard textLength > 0,
              !codeBlockBackgroundRanges.isEmpty else {
            return []
        }

        layoutManager.ensureLayout(for: textContainer)
        let drawingOffset = textContainerOrigin
        var delimiterRects: [NSRect] = []
        let activeBlockRanges = AppMarkdownCodeBlockParser
            .blockCodeRanges(in: string)
            .filter { codeBlockBackgroundRanges.contains($0.contentRange) }
        for delimiterRange in activeBlockRanges.flatMap(\.delimiterRanges) {
            let clampedRange = NSIntersectionRange(delimiterRange, NSRange(location: 0, length: textLength))
            guard clampedRange.length > 0 else {
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                continue
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, _, _, _, _ in
                delimiterRects.append(NSRect(
                    x: self.bounds.minX,
                    y: lineFragmentRect.minY + drawingOffset.y,
                    width: self.bounds.width,
                    height: lineFragmentRect.height
                ))
            }
        }
        return delimiterRects
    }

    private func hiddenCodeBlockDelimiterExclusionPath(in dirtyRect: NSRect) -> NSBezierPath? {
        let delimiterRects = hiddenCodeBlockDelimiterRects().filter { $0.intersects(dirtyRect) }
        guard !delimiterRects.isEmpty else {
            return nil
        }

        // Hidden delimiter glyphs can still contribute selection and text drawing.
        // Clip their rows out of `super.draw(_:)` so selections like Cmd+A do not
        // reveal full-width highlight bars for invisible fences.
        let clipPath = NSBezierPath(rect: bounds.intersection(dirtyRect))
        for rect in delimiterRects {
            clipPath.appendRect(rect)
        }
        clipPath.windingRule = .evenOdd
        return clipPath
    }

    private func codeBlockBackgroundRectWithOuterGaps(
        _ rect: NSRect,
        for characterRange: NSRange,
        layoutManager: NSLayoutManager,
        drawingOffset: NSPoint
    ) -> NSRect {
        let outerGap = AppTextEditorCodeBlockStyling.codeBlockOuterGap
        let minimumHeight = ceil(layoutManager.defaultLineHeight(for: baseTextFont)) +
            (AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2)
        var adjustedRect = rect
        var maxYLimit: CGFloat?

        // A leading fence is hidden but still participates in text layout. Pin only an
        // empty leading block to the normal text inset; once the block has visible code,
        // anchoring from the content line preserves symmetric internal padding.
        if shouldPinLeadingEmptyCodeBlock(characterRange) {
            adjustedRect.origin.y = textContainerInset.height
        }

        if let previousMaxY = visibleLineMaxYBeforeCodeBlock(
            for: characterRange,
            layoutManager: layoutManager,
            drawingOffset: drawingOffset
        ) {
            let newMinY = min(max(adjustedRect.minY, previousMaxY + outerGap), adjustedRect.maxY)
            adjustedRect.size.height = adjustedRect.maxY - newMinY
            adjustedRect.origin.y = newMinY
        }

        if let nextMinY = visibleLineMinYAfterCodeBlock(
            for: characterRange,
            layoutManager: layoutManager,
            drawingOffset: drawingOffset
        ) {
            maxYLimit = nextMinY - outerGap
            adjustedRect.size.height = max(min(adjustedRect.maxY, maxYLimit ?? adjustedRect.maxY) - adjustedRect.minY, 0)
        }

        if adjustedRect.height < minimumHeight {
            let desiredMaxY = adjustedRect.minY + minimumHeight
            let clampedMaxY = min(desiredMaxY, maxYLimit ?? desiredMaxY)
            adjustedRect.size.height = max(clampedMaxY - adjustedRect.minY, 0)
        }

        return adjustedRect
    }

    private func shouldPinLeadingEmptyCodeBlock(_ characterRange: NSRange) -> Bool {
        guard let blockRange = codeBlockRange(matching: characterRange),
              let openingDelimiterRange = blockRange.delimiterRanges.first else {
            return false
        }

        let content = (string as NSString).substring(with: blockRange.contentRange)
        return openingDelimiterRange.location == 0 &&
            content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func trailingEditableCodeLineFragmentRect(
        after characterRange: NSRange,
        layoutManager: NSLayoutManager
    ) -> NSRect? {
        // `NSLayoutManager` gives a trailing newline a caret position on the
        // next visual line, but no used glyph rect. Add that synthetic line so
        // the code-block chrome grows with the caret during keyboard insertion.
        guard let blockRange = codeBlockRange(matching: characterRange),
              blockRange.delimiterRanges.count == 1 || blockRange.delimiterRanges.isEmpty,
              characterRange.length > 0 else {
            return nil
        }

        let nsText = string as NSString
        guard NSMaxRange(characterRange) <= nsText.length,
              nsText.substring(with: characterRange).hasSuffix("\n") else {
            return nil
        }

        if NSMaxRange(characterRange) >= nsText.length,
           !layoutManager.extraLineFragmentUsedRect.isEmpty {
            return layoutManager.extraLineFragmentRect
        }

        guard let previousLineRect = lineFragmentRect(
            containingCharacterAt: max(NSMaxRange(characterRange) - 1, characterRange.location),
            layoutManager: layoutManager
        ) else {
            return nil
        }
        return NSRect(
            x: previousLineRect.minX,
            y: previousLineRect.maxY,
            width: previousLineRect.width,
            height: max(previousLineRect.height, ceil(layoutManager.defaultLineHeight(for: baseTextFont)))
        )
    }

    private func visibleLineMaxYBeforeCodeBlock(
        for characterRange: NSRange,
        layoutManager: NSLayoutManager,
        drawingOffset: NSPoint
    ) -> CGFloat? {
        guard let blockRange = codeBlockRange(matching: characterRange) else {
            return nil
        }
        let previousLocation = blockRange.delimiterRanges.first?.location ?? characterRange.location
        guard previousLocation > 0,
              let lineRect = lineFragmentRect(containingCharacterAt: previousLocation - 1, layoutManager: layoutManager) else {
            return nil
        }

        return lineRect.maxY + drawingOffset.y
    }

    private func visibleLineMinYAfterCodeBlock(
        for characterRange: NSRange,
        layoutManager: NSLayoutManager,
        drawingOffset: NSPoint
    ) -> CGFloat? {
        let nsText = string as NSString
        let textLength = nsText.length
        guard let blockRange = codeBlockRange(matching: characterRange) else {
            return nil
        }

        var nextLocation = blockRange.delimiterRanges.dropFirst().first.map(NSMaxRange) ?? NSMaxRange(characterRange)
        if nextLocation < textLength,
           nsText.character(at: nextLocation) == 0x0A,
           nextLocation + 1 < textLength {
            nextLocation += 1
        }
        guard nextLocation < textLength,
              let lineRect = lineFragmentRect(containingCharacterAt: nextLocation, layoutManager: layoutManager) else {
            return nil
        }

        return lineRect.minY + drawingOffset.y
    }

    private func codeBlockRange(matching characterRange: NSRange) -> AppMarkdownBlockCodeRange? {
        AppMarkdownCodeBlockParser.blockCodeRanges(in: string).first { blockRange in
            blockRange.contentRange.location == characterRange.location &&
                blockRange.contentRange.length == characterRange.length
        } ?? codeBlockBackgroundRanges.first {
            $0.location == characterRange.location && $0.length == characterRange.length
        }.map { range in
            AppMarkdownBlockCodeRange(contentRange: range, delimiterRanges: [])
        }
    }

    private func lineFragmentRect(
        containingCharacterAt location: Int,
        layoutManager: NSLayoutManager
    ) -> NSRect? {
        let textLength = (string as NSString).length
        guard textLength > 0 else {
            return nil
        }

        let characterIndex = min(max(location, 0), textLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }

        return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }
}
