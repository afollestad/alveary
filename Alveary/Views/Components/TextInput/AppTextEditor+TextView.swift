@preconcurrency import AppKit

/// `NSTextView` subclass that owns AppKit-specific text-input rendering.
///
/// SwiftUI hosts pass text and styling ranges into this view, but chips, inline
/// hints, fenced code-block chrome, placeholder drawing, and first-responder
/// behavior need AppKit geometry to stay aligned with the insertion point.
final class AppKitTextView: NSTextView {
    var textLayoutReadyForDrawing = false
    var textLayoutPrimedWidth: CGFloat = 0

    var baseTextFont: NSFont = .preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }

    var showsDisabledCursor = false {
        didSet {
            guard oldValue != showsDisabledCursor else { return }
            window?.invalidateCursorRects(for: self)
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

    var codeBlockBackgroundRanges: [NSRange] = [] {
        didSet {
            needsDisplay = true
        }
    }

    var enablesCodeBlockEditing = false

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
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onShouldChangeText: ((NSRange, String?) -> Bool)?

    // `NSTextView` opts into vibrancy by default, which can make custom-drawn
    // inline-code, slash-command, and mention chip fills composite differently
    // from SwiftUI accent surfaces. Forcing vibrancy off keeps AppKit-drawn
    // chip fills pinned to the literal `NSColor` used by the rest of the UI.
    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard canDrawTextLayoutSafely() else {
            if string.isEmpty, !placeholder.isEmpty {
                drawPlaceholder(in: dirtyRect)
            }
            return
        }
        if string.isEmpty, !placeholder.isEmpty, codeBlockBackgroundRanges.isEmpty {
            drawPlaceholder(in: dirtyRect)
        } else {
            drawCodeBlockBackgrounds(in: dirtyRect)
            drawInlineCodeBackgrounds(in: dirtyRect)
            drawTextChipBackgrounds(in: dirtyRect)
        }
        drawTextExcludingHiddenCodeBlockDelimiters(in: dirtyRect)
        if !string.isEmpty {
            drawCompactChipLabels(in: dirtyRect)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Empty visual code blocks draw their own chrome while AppKit still
        // positions the caret from an invisible extra line fragment. Align the
        // insertion point to the block's content inset so it lands where the
        // first typed code line will appear.
        if enablesCodeBlockEditing,
           !flag,
           eraseEmptyCodeBlockInsertionPoint(from: rect) {
            return
        }
        // The on phase must use the same adjusted rect as the off phase above;
        // otherwise blinking leaves a small remnant at AppKit's original rect.
        super.drawInsertionPoint(
            in: codeBlockInsertionPointRect(from: rect) ?? rect,
            color: color,
            turnedOn: flag
        )
    }

    override func mouseDown(with event: NSEvent) {
        primeTextLayoutForInteraction()
        if isEditable || isSelectable {
            window?.makeFirstResponder(self)
        }
        let point = convert(event.locationInWindow, from: nil)
        if enablesCodeBlockEditing,
           let insertionRange = emptyCodeBlockInsertionRange(at: point) {
            setSelectedRange(insertionRange)
            ensureCodeBlockTypingAttributesIfNeeded(at: insertionRange.location)
            notifyDelegateSelectionChanged()
            return
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func didChangeText() {
        markTextLayoutNeedsPriming()
        super.didChangeText()
        resetEmptyTextTypingAttributesIfNeeded()
        if enablesCodeBlockEditing {
            normalizeCodeBlockSelectionAfterTextMutation()
        }
        needsDisplay = true
        updateInlineHintView()
    }

    override func becomeFirstResponder() -> Bool {
        primeTextLayoutForInteraction()
        resetEmptyTextTypingAttributesIfNeeded()
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if let onShouldChangeText,
           !onShouldChangeText(affectedCharRange, replacementString) {
            return false
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func setSelectedRange(_ charRange: NSRange) {
        guard enablesCodeBlockEditing else {
            super.setSelectedRange(charRange)
            return
        }

        setSelectedRangeWithoutCodeBlockNormalization(normalizedCodeBlockInsertionRange(charRange))
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        guard enablesCodeBlockEditing else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
            return
        }

        let normalizedRanges = ranges.map { NSValue(range: normalizedCodeBlockInsertionRange($0.rangeValue)) }
        super.setSelectedRanges(normalizedRanges, affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard enablesCodeBlockEditing else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        if replacementRange.location == NSNotFound {
            let normalizedSelection = normalizedCodeBlockInsertionRange(selectedRange())
            if normalizedSelection != selectedRange() {
                setSelectedRangeWithoutCodeBlockNormalization(normalizedSelection)
            }
            ensureCodeBlockTypingAttributesIfNeeded(at: normalizedSelection.location)
            let normalizedInsert = openingFenceNormalizedInsertText(insertString, at: normalizedSelection.location)
            super.insertText(normalizedInsert.value, replacementRange: replacementRange)
            applyCodeBlockPostInsertionSelection(normalizedInsert.selectionLocation)
            return
        }

        let normalizedReplacementRange = normalizedCodeBlockInsertionRange(replacementRange)
        ensureCodeBlockTypingAttributesIfNeeded(at: normalizedReplacementRange.location)
        let normalizedInsert = openingFenceNormalizedInsertText(insertString, at: normalizedReplacementRange.location)
        super.insertText(
            normalizedInsert.value,
            replacementRange: normalizedReplacementRange
        )
        applyCodeBlockPostInsertionSelection(normalizedInsert.selectionLocation)
    }

    override func deleteBackward(_ sender: Any?) {
        if enablesCodeBlockEditing,
           deleteTrailingOutsideLineAfterHiddenClosingFenceIfNeeded() || unwrapCodeBlockAtContentStartIfNeeded() {
            return
        }

        super.deleteBackward(sender)
    }

    @available(macOS, deprecated: 10.11)
    override func insertText(_ insertString: Any) {
        guard enablesCodeBlockEditing else {
            super.insertText(insertString)
            return
        }

        let normalizedSelection = normalizedCodeBlockInsertionRange(selectedRange())
        if normalizedSelection != selectedRange() {
            setSelectedRangeWithoutCodeBlockNormalization(normalizedSelection)
        }
        ensureCodeBlockTypingAttributesIfNeeded(at: normalizedSelection.location)
        let normalizedInsert = openingFenceNormalizedInsertText(insertString, at: normalizedSelection.location)
        super.insertText(normalizedInsert.value)
        applyCodeBlockPostInsertionSelection(normalizedInsert.selectionLocation)
    }

    override func layout() {
        updateTextContainerForCurrentBounds()
        super.layout()
        if !string.isEmpty {
            primeTextLayoutForDrawing()
        }
        updateInlineHintView()
        needsDisplay = true
    }

    override func resetCursorRects() {
        guard !showsDisabledCursor else {
            addCursorRect(bounds, cursor: .operationNotAllowed)
            return
        }

        super.resetCursorRects()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !showsDisabledCursor else {
            NSCursor.operationNotAllowed.set()
            return
        }

        super.cursorUpdate(with: event)
    }

    private func drawPlaceholder(in dirtyRect: NSRect) {
        let lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let placeholderRect = NSRect(
            x: textContainerInset.width + lineFragmentPadding,
            y: textContainerInset.height,
            width: max(bounds.width - (textContainerInset.width * 2) - (lineFragmentPadding * 2), 0),
            height: max(bounds.height - (textContainerInset.height * 2), 0)
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseTextFont,
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: NSParagraphStyle.default
        ]

        guard placeholderRect.intersects(dirtyRect) else {
            return
        }

        (placeholder as NSString).draw(
            with: placeholderRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func resetEmptyTextTypingAttributesIfNeeded() {
        guard string.isEmpty else {
            return
        }

        // Clearing a code block can leave AppKit's insertion attributes carrying
        // the code-block paragraph indent. Reset them so the empty caret and
        // placeholder return to the normal text origin.
        typingAttributes = AppTextEditorCodeBlockStyling.baseTypingAttributes(
            font: baseTextFont,
            foregroundColor: .labelColor
        )
    }

    func refreshInlineHintView() {
        updateTextContainerForCurrentBounds()
        updateInlineHintView()
    }

    private func updateInlineHintView() {
        updateTextContainerForCurrentBounds()
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
              let textContainer,
              prepareForSafeTextLayout() else {
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
