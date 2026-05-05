@preconcurrency import AppKit

extension AppKitTextView {
    // For compact file-mention chips, the stored text is percent-encoded (so the
    // mention regex matches it as a single unit) while the chip should visually read
    // as a decoded `@<basename>`. The stored glyphs are drawn clear by
    // `applyCompactFileMentionAttributes`; this method draws the decoded label over
    // the same rect so the user sees the human-readable filename. `textChipDisplayMode`
    // already gates compact mode on a single-line chip, so each chip has at most one
    // enclosing rect — draw into its leading glyph position to keep alignment with the
    // `@` the stored text would have rendered there.
    func drawCompactChipLabels(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              prepareForSafeTextLayout(),
              !textChips.isEmpty else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let drawingOffset = textContainerOrigin
        let attributes = compactChipLabelAttributes

        for chip in textChips where chip.style == .fileMention {
            guard case .compactLabel(let storedDisplayText) = textChipDisplayMode(for: chip) else {
                continue
            }

            let textLength = (string as NSString).length
            let clampedRange = NSIntersectionRange(chip.range, NSRange(location: 0, length: textLength))
            guard clampedRange.length > 0 else {
                continue
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                continue
            }

            let decodedLabel = CanonicalPath.decodeStoredMentionPath(storedDisplayText)

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { enclosingRect, _ in
                let drawRect = NSRect(
                    x: enclosingRect.minX + drawingOffset.x,
                    y: enclosingRect.minY + drawingOffset.y,
                    width: enclosingRect.width,
                    height: enclosingRect.height
                )
                guard drawRect.intersects(dirtyRect) else {
                    return
                }
                (decodedLabel as NSString).draw(
                    with: drawRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes
                )
            }
        }
    }

    private var compactChipLabelAttributes: [NSAttributedString.Key: Any] {
        // Match `AppTextEditorCodeBlockStyling.textChipAttributes` exactly — the
        // stored glyph font and decoded-label font must align for kern compression.
        let chipFont = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize * 0.94,
            weight: .regular
        )
        return [
            .font: chipFont,
            .foregroundColor: AppMarkdownCodeBlockPalette.composerChipForegroundNSColor
        ]
    }
}
