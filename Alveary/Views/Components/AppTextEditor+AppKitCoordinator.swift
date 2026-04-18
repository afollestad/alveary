@preconcurrency import AppKit
import SwiftUI

@MainActor
final class AppKitTextEditorCoordinator: NSObject, NSTextViewDelegate {
    var parent: AppKitTextEditorView
    weak var textView: AppKitTextView?
    weak var scrollView: AppKitTextEditorScrollView?
    var suppressCallbacks = false
    var lastLaidOutTextWidth: CGFloat = 0
    private var selectionRestyleScheduled = false
    private var lastConsumedFocusRequestToken: UUID?
    private var firstResponderClaimInFlight = false

    init(parent: AppKitTextEditorView) {
        self.parent = parent
    }

    func attach(textView: AppKitTextView, scrollView: AppKitTextEditorScrollView) {
        self.textView = textView
        self.scrollView = scrollView
    }

    func applyConfiguration(from parent: AppKitTextEditorView) {
        guard let textView else {
            return
        }

        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.isEditable = !parent.isDisabled
        textView.isSelectable = true
        textView.textColor = .labelColor
        textView.placeholder = parent.placeholder ?? ""
        textView.inlineHint = parent.inlineHint
        syncInlineCodePresentation(for: textView)
        syncTextChipPresentation(for: textView)
        textView.textContainerInset = NSSize(width: parent.horizontalPadding, height: parent.verticalPadding)
        applyTextHighlights()
        textView.refreshInlineHintView()
        textView.needsDisplay = true
    }

    func syncTextIfNeeded() {
        guard let textView, textView.string != parent.text else {
            if let textView {
                syncInlineCodePresentation(for: textView)
            }
            applyTextHighlights()
            return
        }

        suppressCallbacks = true
        textView.string = parent.text
        suppressCallbacks = false
        syncInlineCodePresentation(for: textView)
        syncTextChipPresentation(for: textView)
        applyTextHighlights()
        textView.refreshInlineHintView()
        textView.needsDisplay = true
    }

    func syncSelectionIfNeeded() {
        guard let textView,
              let selection = parent.selection else {
            return
        }

        guard let nsRange = nsRange(for: selection.wrappedValue, in: parent.text) else {
            syncSelectionBinding(with: textView)
            return
        }

        guard textView.selectedRange() != nsRange else {
            return
        }

        suppressCallbacks = true
        textView.setSelectedRange(nsRange)
        suppressCallbacks = false
    }

    func syncFocusIfNeeded() {
        guard let textView, let focus = parent.focus, focus.wrappedValue else {
            return
        }

        guard textView.window?.firstResponder !== textView else {
            return
        }

        claimFirstResponder(on: textView, retriesRemaining: 6)
    }

    // Claims AppKit first responder in response to a programmatic focus request
    // (`parent.requestFirstResponder`). The token bypasses @FocusState because
    // @FocusState programmatic writes don't propagate to view updates unless a
    // `.focused($state)` modifier is attached in the SwiftUI hierarchy — which this
    // NSView bridge deliberately doesn't use. The token is a plain value SwiftUI
    // compares across renders, so a change here reliably fires `updateNSView`; once
    // the AppKit side becomes first responder, `handleFocusChange(true)` then writes
    // the @FocusState back to `true` through the existing bidirectional path.
    func syncFocusRequestIfNeeded() {
        guard let textView,
              let token = parent.requestFirstResponder,
              token != lastConsumedFocusRequestToken else {
            return
        }
        lastConsumedFocusRequestToken = token
        claimFirstResponder(on: textView, retriesRemaining: 6)
        if let onConsumed = parent.onFocusRequestConsumed {
            DispatchQueue.main.async {
                onConsumed()
            }
        }
    }

    // Retries across a handful of main-runloop ticks because the focus-claim path may
    // run before the NSTextView is attached to an NSWindow (SwiftUI composes the
    // representable's container into the hierarchy across multiple passes). Without
    // the retry, a focus claim that coincides with a brand-new view mount — e.g. ⌘N
    // creating a fresh composer that needs focus on first display — lands on a
    // window-less text view and silently no-ops.
    //
    // Deduplicates via `firstResponderClaimInFlight` so repeated `updateNSView` passes
    // during the attachment window don't stack parallel retry chains; the flag stays
    // set across each `scheduleFirstResponderClaim` hop and only clears on a terminal
    // outcome (claim succeeded, already first responder, or retries exhausted).
    private func claimFirstResponder(on textView: NSTextView, retriesRemaining: Int) {
        guard !firstResponderClaimInFlight else {
            return
        }
        firstResponderClaimInFlight = true
        scheduleFirstResponderClaim(on: textView, retriesRemaining: retriesRemaining)
    }

    private func scheduleFirstResponderClaim(on textView: NSTextView, retriesRemaining: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if textView.window?.firstResponder === textView {
                self.firstResponderClaimInFlight = false
                return
            }
            if let window = textView.window {
                window.makeFirstResponder(textView)
                self.firstResponderClaimInFlight = false
                return
            }
            guard retriesRemaining > 0 else {
                self.firstResponderClaimInFlight = false
                return
            }
            self.scheduleFirstResponderClaim(on: textView, retriesRemaining: retriesRemaining - 1)
        }
    }

    func handleFocusChange(_ isFocused: Bool) {
        parent.isAppKitFirstResponder?.wrappedValue = isFocused
        guard let focus = parent.focus, focus.wrappedValue != isFocused else {
            return
        }

        focus.wrappedValue = isFocused
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
            return
        }

        if !suppressCallbacks {
            parent.text = textView.string
        }
        if let textView = textView as? AppKitTextView {
            syncInlineCodePresentation(for: textView)
            syncTextChipPresentation(for: textView)
        }
        applyTextHighlights()
        recalculateHeight()
        updateSelection(from: textView)
    }

    private func syncInlineCodePresentation(for textView: AppKitTextView) {
        textView.inlineCodeBackgroundRanges = parent.inlineCodeBackgroundRanges?(textView.string) ?? []
        textView.inlineCodeBackgroundColor = AppMarkdownCodeBlockPalette.inlineFillNSColor
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
            return
        }

        updateSelection(from: textView)
        refreshTypingAttributes()
        scheduleSelectionRestyle()
    }

    func textDidBeginEditing(_ notification: Notification) {
        handleFocusChange(true)
    }

    func textDidEndEditing(_ notification: Notification) {
        handleFocusChange(false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let key = AppTextEditorKey(selector: commandSelector),
              parent.keyPressKeys.contains(key),
              let handler = parent.onKeyPress else {
            return false
        }

        let modifiers = NSApp.currentEvent?.modifierFlags.eventModifiers ?? []
        let result = handler(AppTextEditorKeyPress(key: key, modifiers: modifiers))
        return result == .handled
    }

    func recalculateHeight() {
        guard let textView,
              let scrollView,
              let layoutManager = textView.layoutManager,
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

        layoutManager.ensureLayout(for: textContainer)
        let lineHeight = layoutManager.defaultLineHeight(for: textView.baseTextFont)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let contentHeight = ceil(max(usedHeight, lineHeight) + (textView.textContainerInset.height * 2))

        if abs(textView.frame.height - max(contentHeight, scrollView.contentSize.height)) > 0.5 {
            textView.frame.size.height = max(contentHeight, scrollView.contentSize.height)
        }

        if abs(parent.measuredTextHeight - contentHeight) > 0.5 {
            parent.measuredTextHeight = contentHeight
        }
    }

    private func updateSelection(from textView: NSTextView) {
        guard !suppressCallbacks,
              parent.selection != nil else {
            return
        }

        syncSelectionBinding(with: textView)
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
            self.textView?.needsDisplay = true
        }
    }

    private func textSelection(for range: NSRange, in text: String) -> TextSelection? {
        guard let stringRange = Range(range, in: text) else {
            return nil
        }

        if range.length == 0 {
            return TextSelection(insertionPoint: stringRange.lowerBound)
        }
        return TextSelection(range: stringRange)
    }

    private func syncSelectionBinding(with textView: NSTextView) {
        guard let selection = parent.selection,
              let textSelection = textSelection(for: textView.selectedRange(), in: textView.string) else {
            return
        }

        if selection.wrappedValue != textSelection {
            selection.wrappedValue = textSelection
        }
    }

    private func nsRange(for selection: TextSelection?, in text: String) -> NSRange? {
        guard let selection else {
            return nil
        }

        switch selection.indices {
        case .selection(let range):
            return nsRange(for: range, in: text)
        case .multiSelection(let rangeSet):
            guard let firstRange = rangeSet.ranges.first else {
                return nil
            }
            return nsRange(for: firstRange, in: text)
        @unknown default:
            return nil
        }
    }

    private func nsRange(for range: Range<String.Index>, in text: String) -> NSRange? {
        let utf16 = text.utf16
        guard let lowerBound = range.lowerBound.samePosition(in: utf16),
              let upperBound = range.upperBound.samePosition(in: utf16) else {
            return nil
        }

        let location = utf16.distance(from: utf16.startIndex, to: lowerBound)
        let length = utf16.distance(from: lowerBound, to: upperBound)
        return NSRange(location: location, length: length)
    }
}

extension AppKitTextEditorView {
    typealias Coordinator = AppKitTextEditorCoordinator
}

private extension AppTextEditorKey {
    init?(selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            self = .upArrow
        case #selector(NSResponder.moveDown(_:)):
            self = .downArrow
        case #selector(NSResponder.insertTab(_:)):
            self = .tab
        case #selector(NSResponder.cancelOperation(_:)):
            self = .escape
        case #selector(NSResponder.insertNewline(_:)):
            self = .return
        default:
            return nil
        }
    }
}

private extension NSEvent.ModifierFlags {
    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []

        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.control) {
            modifiers.insert(.control)
        }
        if contains(.option) {
            modifiers.insert(.option)
        }
        if contains(.command) {
            modifiers.insert(.command)
        }
        if contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if contains(.numericPad) {
            modifiers.insert(.numericPad)
        }

        return modifiers
    }
}
