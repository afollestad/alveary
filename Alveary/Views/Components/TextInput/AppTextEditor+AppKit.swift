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
    enum Result: Equatable {
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
    let reportsMeasuredTextHeight: Bool
    let placeholder: String?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let isDisabled: Bool
    let showsDisabledCursor: Bool
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
    // Programmatic focus requests go through this token instead of writing to `focus`
    // directly. Writing a @FocusState binding from code only propagates to SwiftUI
    // focus tracking when a `.focused($state)` modifier exists somewhere in the view
    // hierarchy — this NSView bridge has none, so programmatic writes previously
    // no-op'd (the @FocusState storage updated but no view re-render fired, so
    // updateNSView still read `focus.wrappedValue == false`). The token is a plain
    // value that SwiftUI compares across renders, so a change here reliably triggers
    // `updateNSView`, where the coordinator then claims AppKit first responder
    // directly and lets `handleFocusChange` backfill the @FocusState.
    let requestFirstResponder: UUID?
    let onFocusRequestConsumed: (() -> Void)?
    // AppKit→SwiftUI signal that the NSTextView is first responder. Writes to a plain
    // `Binding<Bool>` propagate through SwiftUI's normal state-tracking path, whereas
    // writes to `focus: FocusState<Bool>.Binding?` — which also happen in
    // `handleFocusChange` — don't reliably invalidate view descendants here because
    // Some NSViewRepresentable hosts have no `.focused($state)` anchor in their
    // view hierarchy. Features that need body-time first-responder state should
    // drive off this plain binding.
    let isAppKitFirstResponder: Binding<Bool>?
    let disablesAppKitDragDestination: Bool

    @Environment(\.colorScheme) var colorScheme

    init(
        text: Binding<String>,
        selection: Binding<TextSelection?>? = nil,
        measuredTextHeight: Binding<CGFloat>,
        reportsMeasuredTextHeight: Bool = true,
        placeholder: String?,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        isDisabled: Bool,
        showsDisabledCursor: Bool = false,
        focus: FocusState<Bool>.Binding?,
        textHighlightRanges: ((String) -> [NSRange])? = nil,
        textChips: ((String) -> [AppTextEditorChip])? = nil,
        codeBlockRanges: ((String) -> [NSRange])? = nil,
        inlineCodeBackgroundRanges: ((String) -> [NSRange])? = nil,
        inlineCodeRanges: ((String) -> [NSRange])? = nil,
        inlineCodeDelimiterRanges: ((String) -> [NSRange])? = nil,
        inlineHint: AppTextEditorInlineHint? = nil,
        keyPressKeys: Set<AppTextEditorKey>,
        onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)?,
        requestFirstResponder: UUID? = nil,
        onFocusRequestConsumed: (() -> Void)? = nil,
        isAppKitFirstResponder: Binding<Bool>? = nil,
        disablesAppKitDragDestination: Bool = false
    ) {
        _text = text
        self.selection = selection
        _measuredTextHeight = measuredTextHeight
        self.reportsMeasuredTextHeight = reportsMeasuredTextHeight
        self.placeholder = placeholder
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isDisabled = isDisabled
        self.showsDisabledCursor = showsDisabledCursor
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
        self.requestFirstResponder = requestFirstResponder
        self.onFocusRequestConsumed = onFocusRequestConsumed
        self.isAppKitFirstResponder = isAppKitFirstResponder
        self.disablesAppKitDragDestination = disablesAppKitDragDestination
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AppKitTextEditorContainerView {
        let containerView = AppKitTextEditorContainerView(frame: .zero)
        let scrollView = makeScrollView()
        let textView = makeTextView(context: context)
        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        containerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.attach(containerView: containerView, textView: textView, scrollView: scrollView)
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.handleLayoutChange()
        }
        context.coordinator.applyConfiguration(from: self)
        context.coordinator.recalculateHeight()

        return containerView
    }

    private func makeTextView(context: Context) -> AppKitTextView {
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
        textView.onKeyEquivalent = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyEquivalent(event) ?? false
        }

        return textView
    }

    private func makeScrollView() -> AppKitTextEditorScrollView {
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

        let clipView = AppKitTextEditorClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        return scrollView
    }

    func updateNSView(_ containerView: AppKitTextEditorContainerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyConfiguration(from: self)
        context.coordinator.syncTextIfNeeded()
        context.coordinator.syncSelectionIfNeeded()
        context.coordinator.syncFocusIfNeeded()
        context.coordinator.syncFocusRequestIfNeeded()
        context.coordinator.recalculateHeight()
    }
}

final class AppKitTextEditorScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var showsDisabledCursor = false {
        didSet {
            guard oldValue != showsDisabledCursor else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        // Hit testing can land on the scroll or clip wrapper when the editor
        // fills the composer. Focus the document view before AppKit starts
        // selection tracking so clicks behave like they hit `NSTextView`.
        guard focusDocumentTextView() else {
            super.mouseDown(with: event)
            return
        }
        documentView?.mouseDown(with: event)
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
}

final class AppKitTextEditorClipView: NSClipView {
    var showsDisabledCursor = false {
        didSet {
            guard oldValue != showsDisabledCursor else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // See `AppKitTextEditorScrollView.mouseDown(with:)`; both wrapper
        // layers can receive the first click depending on composer layout.
        guard focusDocumentTextView() else {
            super.mouseDown(with: event)
            return
        }
        documentView?.mouseDown(with: event)
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
}

private extension NSView {
    func focusDocumentTextView() -> Bool {
        let textView: AppKitTextView?
        if let scrollView = self as? NSScrollView {
            textView = scrollView.documentView as? AppKitTextView
        } else if let clipView = self as? NSClipView {
            textView = clipView.documentView as? AppKitTextView
        } else {
            textView = nil
        }

        guard let textView else {
            return false
        }
        textView.primeTextLayoutForInteraction()
        return window?.makeFirstResponder(textView) == true
    }
}

final class AppKitTextEditorContainerView: NSView {
    var showsDisabledCursor = false {
        didSet {
            guard oldValue != showsDisabledCursor else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isFlipped: Bool {
        true
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
}
