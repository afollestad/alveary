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
    // `ChatInputField` has no `.focused($state)` anchor in its view hierarchy. Features
    // that need to read "is the composer actively focused?" during body evaluation (e.g.
    // the inline slash-command hint) should drive off this plain binding.
    let isAppKitFirstResponder: Binding<Bool>?
    let disablesAppKitDragDestination: Bool

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
        onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)?,
        requestFirstResponder: UUID? = nil,
        onFocusRequestConsumed: (() -> Void)? = nil,
        isAppKitFirstResponder: Binding<Bool>? = nil,
        disablesAppKitDragDestination: Bool = false
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
        context.coordinator.syncFocusRequestIfNeeded()
        context.coordinator.recalculateHeight()
    }
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
