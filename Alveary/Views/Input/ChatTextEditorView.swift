@preconcurrency import AppKit
import SwiftUI

/// Native chat/composer text editor that owns measurement, selection styling,
/// first-responder handoff, and AppKit text-chip/code highlighting.
///
/// This stays AppKit-owned because Alveary's variable-height transcript and
/// composer UX needs deterministic measurement and first-responder control;
/// SwiftUI lazy/recycling behavior caused scroll-position and performance issues
/// here.
@MainActor
final class ChatTextEditorView: NSView, NSTextViewDelegate {
    private let scrollView = AppKitTextEditorScrollView()
    private let textView = AppKitTextView(frame: .zero)
    private var configuration = ChatTextEditorConfiguration(text: "")
    private var suppressCallbacks = false
    private var lastMeasuredHeight: CGFloat = 0
    private var lastLaidOutTextWidth: CGFloat = 0
    private var lastConsumedFocusRequestToken: UUID?
    private var lastReportedFocus: Bool?
    private var firstResponderClaimInFlight = false
    private var selectionRestyleScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    var textViewForTesting: AppKitTextView {
        textView
    }

    func configure(_ configuration: ChatTextEditorConfiguration) {
        self.configuration = configuration
        applyConfiguration()
        syncTextIfNeeded()
        syncSelectionIfNeeded()
        syncFocusRequestIfNeeded()
        recalculateHeight()
    }

    override func layout() {
        super.layout()
        handleLayoutChange()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else {
            return
        }

        if !suppressCallbacks {
            configuration.text = textView.string
            configuration.onTextChange(textView.string)
        }
        syncInlineCodePresentation()
        syncTextChipPresentation()
        applyTextHighlights()
        recalculateHeight()
        updateSelection(from: textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else {
            return
        }

        updateSelection(from: textView)
        refreshTypingAttributes()
        scheduleSelectionRestyle()
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else {
            return
        }
        reportFocusChange(true)
    }

    func textDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextView === textView else {
            return
        }
        reportFocusChange(false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === self.textView,
              let key = AppTextEditorKey(chatTextEditorSelector: commandSelector) else {
            return false
        }

        return handleKeyPress(key: key, modifiers: NSApp.currentEvent?.modifierFlags.chatTextEditorEventModifiers ?? [])
    }

    private func setupViews() {
        wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.backgroundColor = .clear
        let clipView = AppKitTextEditorClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.onLayout = { [weak self] in
            self?.handleLayoutChange()
        }

        textView.delegate = self
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.font = textView.baseTextFont
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.onFocusChange = { [weak self] isFocused in
            self?.reportFocusChange(isFocused)
        }
        textView.onKeyEquivalent = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }

        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applyConfiguration() {
        let showsDisabledCursor = configuration.isDisabled && configuration.showsDisabledCursor
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.isEditable = !configuration.isDisabled
        textView.isSelectable = !showsDisabledCursor
        textView.showsDisabledCursor = showsDisabledCursor
        scrollView.showsDisabledCursor = showsDisabledCursor
        (scrollView.contentView as? AppKitTextEditorClipView)?.showsDisabledCursor = showsDisabledCursor
        textView.textColor = .labelColor
        textView.placeholder = configuration.placeholder
        textView.inlineHint = configuration.inlineHint
        textView.disablesAppKitDragDestination = configuration.disablesAppKitDragDestination
        textView.textContainerInset = NSSize(
            width: configuration.horizontalPadding,
            height: configuration.verticalPadding
        )
        syncInlineCodePresentation()
        syncTextChipPresentation()
        applyTextHighlights()
        textView.refreshInlineHintView()
        textView.needsDisplay = true
    }

    private func syncTextIfNeeded() {
        guard textView.string != configuration.text else {
            return
        }

        suppressCallbacks = true
        textView.string = configuration.text
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
            actualCharacterRange: nil
        )
        suppressCallbacks = false
        syncInlineCodePresentation()
        syncTextChipPresentation()
        applyTextHighlights()
        textView.refreshInlineHintView()
        textView.needsDisplay = true
    }

    private func syncSelectionIfNeeded() {
        guard let selectedRange = configuration.selectedRange,
              NSMaxRange(selectedRange) <= (textView.string as NSString).length,
              textView.selectedRange() != selectedRange else {
            return
        }

        suppressCallbacks = true
        textView.setSelectedRange(selectedRange)
        suppressCallbacks = false
    }

    private func syncFocusRequestIfNeeded() {
        guard let token = configuration.requestFirstResponder,
              token != lastConsumedFocusRequestToken else {
            return
        }
        lastConsumedFocusRequestToken = token
        claimFirstResponder(retriesRemaining: 6)
        DispatchQueue.main.async { [configuration] in
            configuration.onFocusRequestConsumed()
        }
    }

    private func reportFocusChange(_ isFocused: Bool) {
        guard lastReportedFocus != isFocused else {
            return
        }

        lastReportedFocus = isFocused
        configuration.onFocusChange(isFocused)
    }

    private func claimFirstResponder(retriesRemaining: Int) {
        guard !firstResponderClaimInFlight else {
            return
        }
        firstResponderClaimInFlight = true
        scheduleFirstResponderClaim(retriesRemaining: retriesRemaining)
    }

    private func scheduleFirstResponderClaim(retriesRemaining: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.textView.window?.firstResponder === self.textView {
                self.firstResponderClaimInFlight = false
                return
            }
            if let window = self.textView.window {
                window.makeFirstResponder(self.textView)
                self.firstResponderClaimInFlight = false
                return
            }
            guard retriesRemaining > 0 else {
                self.firstResponderClaimInFlight = false
                return
            }
            self.scheduleFirstResponderClaim(retriesRemaining: retriesRemaining - 1)
        }
    }

    private func handleLayoutChange() {
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

    private func syncInlineCodePresentation() {
        textView.inlineCodeBackgroundRanges = configuration.inlineCodeBackgroundRanges(textView.string)
        textView.inlineCodeBackgroundColor = AppMarkdownCodeBlockPalette.composerChipFillNSColor
    }

    private func syncTextChipPresentation() {
        textView.textChips = configuration.textChips(textView.string)
    }

    private func applyTextHighlights() {
        guard let textStorage = textView.textStorage else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseFont = textView.baseTextFont
        let baseColor = NSColor.labelColor
        let blockRanges = configuration.codeBlockRanges(textView.string)
        let inlineRanges = configuration.inlineCodeRanges(textView.string)
        let inlineDelimiterRanges = configuration.inlineCodeDelimiterRanges(textView.string)
        let compactDisplayChips = compactDisplayChips()
        guard fullRange.length > 0 else {
            textView.typingAttributes = AppTextEditorCodeBlockStyling.baseTypingAttributes(
                font: baseFont,
                foregroundColor: baseColor
            )
            return
        }

        textStorage.beginEditing()
        AppTextEditorCodeBlockStyling.apply(
            to: textStorage,
            context: .init(
                fullRange: fullRange,
                highlightRanges: configuration.textHighlightRanges(textView.string),
                blockRanges: blockRanges,
                inlineRanges: inlineRanges,
                inlineDelimiterRanges: inlineDelimiterRanges,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: configuration.colorScheme
            )
        )
        AppTextEditorCodeBlockStyling.applyTextChips(
            to: textStorage,
            chips: textView.textChips,
            fullRange: fullRange,
            compactDisplayResolver: { chip in
                compactDisplayChips.contains(chip)
            }
        )
        textStorage.endEditing()
        updateTypingAttributes(
            blockRanges: blockRanges,
            inlineRanges: inlineRanges,
            baseFont: baseFont,
            baseColor: baseColor
        )
    }

    private func refreshTypingAttributes() {
        updateTypingAttributes(
            blockRanges: configuration.codeBlockRanges(textView.string),
            inlineRanges: configuration.inlineCodeRanges(textView.string),
            baseFont: textView.baseTextFont,
            baseColor: .labelColor
        )
    }

    private func updateTypingAttributes(
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
                textUTF16Count: textView.string.utf16.count,
                baseFont: baseFont,
                baseColor: baseColor,
                colorScheme: configuration.colorScheme
            )
        )
    }

    private func scheduleSelectionRestyle() {
        guard !selectionRestyleScheduled else {
            return
        }

        selectionRestyleScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.selectionRestyleScheduled = false
            self.applyTextHighlights()
            self.textView.needsDisplay = true
        }
    }

    private func compactDisplayChips() -> [AppTextEditorChip] {
        // `textChipDisplayMode` asks NSLayoutManager for glyph rects, so compute
        // it before `NSTextStorage.beginEditing()`. AppKit raises if glyph layout
        // is forced while attributes are being mutated.
        textView.textChips.filter { chip in
            textView.textChipDisplayMode(for: chip) == .compactLabel(chip.displayText)
        }
    }

    private func updateSelection(from textView: NSTextView) {
        guard !suppressCallbacks else {
            return
        }
        configuration.onSelectionChange(textView.selectedRange())
    }

    private func recalculateHeight() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let availableWidth = scrollView.contentSize.width
        guard availableWidth > 0 else {
            return
        }

        if abs(textView.frame.width - availableWidth) > 0.5 {
            textView.frame.size.width = availableWidth
        }
        textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

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

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let key = AppTextEditorKey(chatTextEditorKeyEquivalentEvent: event) else {
            return false
        }

        return handleKeyPress(key: key, modifiers: event.modifierFlags.chatTextEditorEventModifiers)
    }

    private func handleKeyPress(key: AppTextEditorKey, modifiers: EventModifiers) -> Bool {
        guard configuration.keyPressKeys.contains(key) else {
            return false
        }

        let result = configuration.onKeyPress(AppTextEditorKeyPress(key: key, modifiers: modifiers))
        return result == .handled
    }
}
