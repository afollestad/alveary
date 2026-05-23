@preconcurrency import AppKit
import SwiftUI

/// AppKit-owned chat/composer editor for measurement, selection styling, first-responder handoff,
/// and highlighting.
@MainActor
final class ChatTextEditorView: NSView, NSTextViewDelegate {
    let scrollView = AppKitTextEditorScrollView()
    let textView = AppKitTextView(frame: .zero)
    var configuration = ChatTextEditorConfiguration(text: "")
    var suppressCallbacks = false
    var lastMeasuredHeight: CGFloat = 0
    var lastLaidOutTextWidth: CGFloat = 0
    private var lastConsumedFocusRequestToken: UUID?
    private var lastReportedFocus: Bool?
    private var firstResponderClaimInFlight = false
    var selectionRestyleScheduled = false
    var heightRecalculationScheduled = false
    var isMeasuringLayout = false
    var lastAppliedStylingFingerprint: ChatTextEditorStylingFingerprint?
    var lastAppliedTypingFingerprint: ChatTextEditorTypingFingerprint?
    #if DEBUG
    var presentationApplyCountForTesting = 0
    var typingAttrsApplyCountForTesting = 0
    #endif

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    var textViewForTesting: AppKitTextView { textView }
    var textViewForHitTesting: AppKitTextView { textView }

    override func mouseDown(with event: NSEvent) { focusTextViewForMouseDown(event) }

    func configure(_ configuration: ChatTextEditorConfiguration) {
        self.configuration = configuration
        applyConfiguration()
        syncTextIfNeeded()
        syncSelectionIfNeeded()
        syncFocusIfNeeded()
        syncFocusRequestIfNeeded()
        primeTextLayoutForDisplayIfPossible()
        scheduleHeightRecalculation()
    }

    override func layout() {
        super.layout()
        textView.updateTextContainerForCurrentBounds()
        refreshWidthDependentTextPresentationIfNeeded()
        primeTextLayoutForDisplayIfPossible()
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
        textView.onShouldChangeText = { [weak self] range, replacement in
            self?.configuration.onShouldChangeText?(range, replacement) ?? true
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
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        if textView.baseTextFont != baseFont {
            textView.baseTextFont = baseFont
            textView.font = baseFont
            lastAppliedStylingFingerprint = nil
            lastAppliedTypingFingerprint = nil
        }
        if textView.isEditable != !configuration.isDisabled {
            textView.isEditable = !configuration.isDisabled
        }
        if textView.isSelectable != !showsDisabledCursor {
            textView.isSelectable = !showsDisabledCursor
        }
        if textView.showsDisabledCursor != showsDisabledCursor {
            textView.showsDisabledCursor = showsDisabledCursor
        }
        if scrollView.showsDisabledCursor != showsDisabledCursor {
            scrollView.showsDisabledCursor = showsDisabledCursor
        }
        if (scrollView.contentView as? AppKitTextEditorClipView)?.showsDisabledCursor != showsDisabledCursor {
            (scrollView.contentView as? AppKitTextEditorClipView)?.showsDisabledCursor = showsDisabledCursor
        }
        if textView.placeholder != configuration.placeholder {
            textView.placeholder = configuration.placeholder
        }
        if textView.inlineHint != configuration.inlineHint {
            textView.inlineHint = configuration.inlineHint
        }
        textView.enablesCodeBlockEditing = true
        if textView.disablesAppKitDragDestination != configuration.disablesAppKitDragDestination {
            textView.disablesAppKitDragDestination = configuration.disablesAppKitDragDestination
        }
        let textContainerInset = NSSize(
            width: configuration.horizontalPadding,
            height: configuration.verticalPadding
        )
        if textView.textContainerInset != textContainerInset {
            textView.textContainerInset = textContainerInset
        }
        refreshTextPresentationIfNeeded()
        textView.refreshInlineHintView()
        textView.needsDisplay = true
    }

    private func syncTextIfNeeded() {
        guard textView.string != configuration.text else {
            return
        }

        suppressCallbacks = true
        textView.string = configuration.text
        textView.markTextLayoutNeedsPriming()
        textView.layoutManager?.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
            actualCharacterRange: nil
        )
        lastAppliedStylingFingerprint = nil
        lastAppliedTypingFingerprint = nil
        suppressCallbacks = false
        refreshTextPresentationIfNeeded()
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

    private func refreshWidthDependentTextPresentationIfNeeded() {
        let availableWidth = availableTextWidth
        guard availableWidth > 0,
              abs(availableWidth - lastLaidOutTextWidth) > 0.5 else {
            return
        }

        lastLaidOutTextWidth = availableWidth
        refreshTextPresentationIfNeeded(force: true)
        textView.needsDisplay = true
    }

    /// Primes non-empty text for immediate drawing once AppKit has given the editor a usable width.
    ///
    /// SwiftUI snapshots can capture this view before the deferred height pass runs. `NSTextView.draw(_:)`
    /// intentionally refuses to fill layout holes, so the chat composer must do the layout-manager work
    /// from configuration/layout instead of waiting for the next async measurement turn.
    private func primeTextLayoutForDisplayIfPossible() {
        guard !textView.string.isEmpty,
              textView.updateTextContainerForCurrentBounds() else {
            return
        }

        textView.primeTextLayoutForDrawing()
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

    private func syncFocusIfNeeded() {
        guard configuration.wantsFirstResponder,
              textView.window?.firstResponder !== textView else {
            return
        }

        claimFirstResponder(retriesRemaining: 6)
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

    func handleLayoutChange() {
        guard !isMeasuringLayout else {
            return
        }

        scheduleHeightRecalculation()
    }

    private func updateSelection(from textView: NSTextView) {
        guard !suppressCallbacks else {
            return
        }
        configuration.onSelectionChange(textView.selectedRange())
    }
}
