@preconcurrency import AppKit

/// Caret correction for composer code blocks whose markdown fences are hidden.
extension AppKitTextView {
    func codeBlockInsertionPointRect(from proposedRect: NSRect) -> NSRect? {
        emptyCodeBlockInsertionPointRect(from: proposedRect) ??
            trailingClosedCodeBlockInsertionPointRect(from: proposedRect)
    }

    func emptyCodeBlockInsertionPointRect(from proposedRect: NSRect) -> NSRect? {
        let selection = selectedRange()
        guard selection.length == 0,
              let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: string).first(where: { blockRange in
                  blockRange.contentRange.length == 0 &&
                      selection.location == blockRange.contentRange.location
              }),
              let backgroundRect = codeBlockBackgroundRects(for: blockRange.contentRange).first else {
            return nil
        }

        var rect = proposedRect
        // The proposed rect can come from the hidden delimiter line. Align both
        // blink phases with the first visible code glyph instead.
        rect.origin.x = backgroundRect.minX + AppTextEditorCodeBlockStyling.codeBlockHorizontalPadding
        rect.origin.y = backgroundRect.minY + AppTextEditorCodeBlockStyling.codeBlockVerticalPadding
        rect.size.height = ceil(layoutManager?.defaultLineHeight(for: baseTextFont) ?? proposedRect.height)
        return rect
    }

    func eraseEmptyCodeBlockInsertionPoint(from proposedRect: NSRect) -> Bool {
        guard let rect = codeBlockInsertionPointRect(from: proposedRect),
              NSGraphicsContext.current != nil else {
            return false
        }

        // AppKit's off blink pass erases using its original hidden delimiter
        // rect. Code-block caret corrections move the caret, so erase the same
        // adjusted rect that the on phase draws.
        codeBlockInsertionPointEraseColor(for: rect).setFill()
        rect.fill()
        return true
    }

    private func codeBlockInsertionPointEraseColor(for rect: NSRect) -> NSColor {
        for characterRange in codeBlockBackgroundRanges
            where codeBlockBackgroundRects(for: characterRange).contains(where: { $0.intersects(rect) }) {
            return AppMarkdownCodeBlockPalette.fillNSColor(for: effectiveAppearance)
        }
        return backgroundColor
    }

    private func trailingClosedCodeBlockInsertionPointRect(from proposedRect: NSRect) -> NSRect? {
        let selection = selectedRange()
        guard selection.length == 0,
              let blockRange = AppMarkdownCodeBlockParser.blockCodeRanges(in: string).first(where: { blockRange in
                  guard let closingDelimiter = blockRange.delimiterRanges.dropFirst().first else {
                      return false
                  }
                  return selection.location == NSMaxRange(closingDelimiter)
              }),
              let backgroundRect = codeBlockBackgroundRects(for: blockRange.contentRange).first else {
            return nil
        }

        var rect = proposedRect
        // AppKit proposes EOF carets from the hidden closing-fence row. Draw
        // the caret where the first outside character will appear.
        rect.origin.x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        rect.origin.y = backgroundRect.maxY + AppTextEditorCodeBlockStyling.codeBlockOuterGap
        rect.size.height = ceil(layoutManager?.defaultLineHeight(for: baseTextFont) ?? proposedRect.height)
        return rect
    }
}
