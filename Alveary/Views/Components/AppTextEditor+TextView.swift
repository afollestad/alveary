@preconcurrency import AppKit
import SwiftUI

struct AppTextEditorInlineHint: Equatable {
    let text: String
}

enum AppTextEditorChipDisplayMode: Equatable {
    case fullText
    case compactLabel(String)
}

final class AppTextEditorInlineHintView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    var font: NSFont = .preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }

    var textColor: NSColor = .placeholderTextColor {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        (text as NSString).draw(
            with: bounds.intersection(dirtyRect),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
}

final class AppKitTextView: NSTextView {
    var baseTextFont: NSFont = .preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }

    // When true, suppress NSTextView's built-in drag destination so a parent SwiftUI
    // `.dropDestination` receives file/text drops instead. The composer opts in so it
    // can prepend `@` and collapse dropped paths into mention chips; other editors
    // (Skills instructions, MCP headers/env) leave this false so they keep NSTextView's
    // default behavior of inserting dropped text inline.
    var disablesAppKitDragDestination = false {
        didSet {
            guard oldValue != disablesAppKitDragDestination else { return }
            updateDragTypeRegistration()
        }
    }

    // `updateDragTypeRegistration()` is NSTextView's hook for re-registering drag
    // types whenever state such as `isRichText` or `importsGraphics` changes.
    // Overriding it gates registration on `disablesAppKitDragDestination` so the
    // drag destination stays unregistered even across subsequent NSTextView state
    // changes that would otherwise re-register the default types. Paste uses
    // `readablePasteboardTypes` and is untouched.
    override func updateDragTypeRegistration() {
        if disablesAppKitDragDestination {
            unregisterDraggedTypes()
        } else {
            super.updateDragTypeRegistration()
        }
    }

    var textChips: [AppTextEditorChip] = [] {
        didSet {
            needsDisplay = true
        }
    }

    var inlineCodeBackgroundRanges: [NSRange] = [] {
        didSet {
            needsDisplay = true
        }
    }

    var inlineCodeBackgroundColor: NSColor = .clear {
        didSet {
            needsDisplay = true
        }
    }

    private lazy var inlineHintView: AppTextEditorInlineHintView = {
        let view = AppTextEditorInlineHintView(frame: .zero)
        view.isHidden = true
        return view
    }()

    var onFocusChange: ((Bool) -> Void)?
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }
    var inlineHint: AppTextEditorInlineHint? {
        didSet {
            updateInlineHintView()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if string.isEmpty, !placeholder.isEmpty {
            drawPlaceholder(in: dirtyRect)
        } else {
            drawInlineCodeBackgrounds(in: dirtyRect)
            drawTextChipBackgrounds(in: dirtyRect)
        }
        super.draw(dirtyRect)
        if !string.isEmpty {
            drawCompactChipLabels(in: dirtyRect)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        updateInlineHintView()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange?(true)
            needsDisplay = true
            updateInlineHintView()
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange?(false)
            needsDisplay = true
            updateInlineHintView()
        }
        return didResignFirstResponder
    }

    override func layout() {
        super.layout()
        updateInlineHintView()
        needsDisplay = true
    }

    private func drawPlaceholder(in dirtyRect: NSRect) {
        let lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let placeholderRect = NSRect(
            x: textContainerInset.width + lineFragmentPadding,
            y: textContainerInset.height,
            width: max(bounds.width - (textContainerInset.width * 2) - (lineFragmentPadding * 2), 0),
            height: max(bounds.height - (textContainerInset.height * 2), 0)
        )

        let paragraphStyle = (typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseTextFont,
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraphStyle
        ]

        (placeholder as NSString).draw(
            with: placeholderRect.intersection(dirtyRect),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func drawInlineCodeBackgrounds(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
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

    private func drawTextChipBackgrounds(in dirtyRect: NSRect) {
        let cornerRadius: CGFloat = 4
        AppMarkdownCodeBlockPalette.composerChipFillNSColor.setFill()

        for resolvedChip in resolvedTextChips() {
            for rect in resolvedChip.rects where rect.intersects(dirtyRect) {
                NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            }
        }
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

    func textChipRects(for characterRange: NSRange) -> [NSRect] {
        guard let layoutManager,
              let textContainer else {
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

    private func selectionIntersectsChip(_ chipRange: NSRange) -> Bool {
        let selectionRange = selectedRange()

        if selectionRange.length == 0 {
            return selectionRange.location >= chipRange.location && selectionRange.location < NSMaxRange(chipRange)
        }

        return NSIntersectionRange(selectionRange, chipRange).length > 0
    }

    func refreshInlineHintView() {
        updateInlineHintView()
    }

    private func updateInlineHintView() {
        guard let inlineHint,
              !inlineHint.text.isEmpty,
              !string.isEmpty,
              let hintRect = inlineHintDrawingRect() else {
            inlineHintView.isHidden = true
            return
        }

        if inlineHintView.superview == nil {
            addSubview(inlineHintView)
        }

        inlineHintView.text = inlineHint.text
        inlineHintView.font = baseTextFont
        inlineHintView.textColor = .placeholderTextColor
        inlineHintView.frame = hintRect.integral
        inlineHintView.isHidden = false
    }

    func inlineHintDrawingRect() -> NSRect? {
        guard let layoutManager,
               let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let containerOrigin = textContainerOrigin
        let hintOrigin: CGPoint
        let lineHeight: CGFloat

        if let lineRect = inlineHintLineRect(using: layoutManager, textContainer: textContainer) {
            hintOrigin = CGPoint(
                x: containerOrigin.x + lineRect.maxX,
                y: containerOrigin.y + lineRect.minY
            )
            lineHeight = lineRect.height
        } else {
            let extraLineRect = layoutManager.extraLineFragmentUsedRect
            guard !extraLineRect.isEmpty else {
                return nil
            }
            hintOrigin = CGPoint(
                x: containerOrigin.x + extraLineRect.minX,
                y: containerOrigin.y + extraLineRect.minY
            )
            lineHeight = extraLineRect.height
        }

        return NSRect(
            x: hintOrigin.x,
            y: hintOrigin.y,
            width: max(bounds.width - hintOrigin.x - textContainerInset.width, 0),
            height: max(lineHeight, bounds.height - hintOrigin.y - textContainerInset.height)
        )
    }

    private func inlineHintLineRect(
        using layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard !string.isEmpty else {
            return nil
        }

        let textLength = (string as NSString).length
        let characterIndex = max(textLength - 1, 0)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }

        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
    }
}

private struct ResolvedTextChip {
    let chip: AppTextEditorChip
    let rects: [NSRect]
}
