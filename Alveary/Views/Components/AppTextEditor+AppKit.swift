@preconcurrency import AppKit
import SwiftUI

enum AppTextEditorKey: Hashable {
    case upArrow
    case downArrow
    case tab
    case escape
    case `return`
}

struct AppTextEditorKeyPress {
    enum Result {
        case handled
        case ignored
    }

    let key: AppTextEditorKey
    let modifiers: EventModifiers
}

// NSTextView gives the composer reliable sizing, scrolling, and return-key handling.
struct AppKitTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let selection: Binding<TextSelection?>?
    @Binding var measuredTextHeight: CGFloat
    let placeholder: String?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let isDisabled: Bool
    let focus: FocusState<Bool>.Binding?
    let textHighlightRanges: ((String) -> [NSRange])?
    let textChips: ((String) -> [AppTextEditorChip])?
    let codeBlockRanges: ((String) -> [NSRange])?
    let inlineCodeBackgroundRanges: ((String) -> [NSRange])?
    let inlineCodeRanges: ((String) -> [NSRange])?
    let inlineCodeDelimiterRanges: ((String) -> [NSRange])?
    let inlineHint: AppTextEditorInlineHint?
    let keyPressKeys: Set<AppTextEditorKey>
    let onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)?

    @Environment(\.colorScheme) var colorScheme

    init(
        text: Binding<String>,
        selection: Binding<TextSelection?>? = nil,
        measuredTextHeight: Binding<CGFloat>,
        placeholder: String?,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        isDisabled: Bool,
        focus: FocusState<Bool>.Binding?,
        textHighlightRanges: ((String) -> [NSRange])? = nil,
        textChips: ((String) -> [AppTextEditorChip])? = nil,
        codeBlockRanges: ((String) -> [NSRange])? = nil,
        inlineCodeBackgroundRanges: ((String) -> [NSRange])? = nil,
        inlineCodeRanges: ((String) -> [NSRange])? = nil,
        inlineCodeDelimiterRanges: ((String) -> [NSRange])? = nil,
        inlineHint: AppTextEditorInlineHint? = nil,
        keyPressKeys: Set<AppTextEditorKey>,
        onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)?
    ) {
        _text = text
        self.selection = selection
        _measuredTextHeight = measuredTextHeight
        self.placeholder = placeholder
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isDisabled = isDisabled
        self.focus = focus
        self.textHighlightRanges = textHighlightRanges
        self.textChips = textChips
        self.codeBlockRanges = codeBlockRanges
        self.inlineCodeBackgroundRanges = inlineCodeBackgroundRanges
        self.inlineCodeRanges = inlineCodeRanges
        self.inlineCodeDelimiterRanges = inlineCodeDelimiterRanges
        self.inlineHint = inlineHint
        self.keyPressKeys = keyPressKeys
        self.onKeyPress = onKeyPress
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AppKitTextEditorContainerView {
        let containerView = AppKitTextEditorContainerView(frame: .zero)
        let scrollView = AppKitTextEditorScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.backgroundColor = .clear

        let textView = AppKitTextView(frame: .zero)
        textView.delegate = context.coordinator
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
        textView.textContainerInset = NSSize(width: horizontalPadding, height: verticalPadding)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.handleFocusChange(isFocused)
        }

        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        containerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.attach(textView: textView, scrollView: scrollView)
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.handleLayoutChange()
        }
        context.coordinator.applyConfiguration(from: self)
        context.coordinator.recalculateHeight()

        return containerView
    }

    func updateNSView(_ containerView: AppKitTextEditorContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyConfiguration(from: self)
        context.coordinator.syncTextIfNeeded()
        context.coordinator.syncSelectionIfNeeded()
        context.coordinator.syncFocusIfNeeded()
        context.coordinator.recalculateHeight()
    }
}

@MainActor
final class AppKitTextEditorCoordinator: NSObject, NSTextViewDelegate {
    var parent: AppKitTextEditorView
    weak var textView: AppKitTextView?
    weak var scrollView: AppKitTextEditorScrollView?
    var suppressCallbacks = false
    var lastLaidOutTextWidth: CGFloat = 0
    private var selectionRestyleScheduled = false

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

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }

    func handleFocusChange(_ isFocused: Bool) {
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

final class AppKitTextEditorScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class AppKitTextEditorContainerView: NSView {
    override var isFlipped: Bool {
        true
    }
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
