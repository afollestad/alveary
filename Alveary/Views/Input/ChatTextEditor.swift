import AppKit
import SwiftUI

/// SwiftUI bridge for the native composer editor.
///
/// The composer shell is still SwiftUI-owned in this slice; this bridge keeps
/// text measurement, focus, and chip drawing on the shared AppKit editor path.
struct ChatTextEditor: View {
    @Binding private var text: String
    @State private var measuredTextHeight: CGFloat = 0

    private let selection: Binding<TextSelection?>?
    private let minHeight: CGFloat
    private let idealHeight: CGFloat?
    private let maxHeight: CGFloat?
    private let placeholder: String
    private let cornerRadius: CGFloat
    private let cornerRadii: RectangleCornerRadii?
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let backgroundColor: Color
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let isDisabled: Bool
    private let showsDisabledCursor: Bool
    private let focus: FocusState<Bool>.Binding?
    private let textHighlightRanges: (String) -> [NSRange]
    private let textChips: (String) -> [AppTextEditorChip]
    private let codeBlockRanges: (String) -> [NSRange]
    private let inlineCodeBackgroundRanges: (String) -> [NSRange]
    private let inlineCodeRanges: (String) -> [NSRange]
    private let inlineCodeDelimiterRanges: (String) -> [NSRange]
    private let inlineHint: AppTextEditorInlineHint?
    private let keyPressKeys: Set<AppTextEditorKey>
    private let onKeyPress: (AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result
    private let requestFirstResponder: UUID?
    private let onFocusRequestConsumed: () -> Void
    private let isAppKitFirstResponder: Binding<Bool>?
    private let disablesAppKitDragDestination: Bool

    init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        minHeight: CGFloat,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        placeholder: String,
        cornerRadius: CGFloat,
        cornerRadii: RectangleCornerRadii? = nil,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        backgroundColor: Color,
        borderColor: Color,
        borderWidth: CGFloat,
        isDisabled: Bool,
        showsDisabledCursor: Bool,
        focus: FocusState<Bool>.Binding?,
        textHighlightRanges: @escaping (String) -> [NSRange] = { _ in [] },
        textChips: @escaping (String) -> [AppTextEditorChip],
        codeBlockRanges: @escaping (String) -> [NSRange],
        inlineCodeBackgroundRanges: @escaping (String) -> [NSRange],
        inlineCodeRanges: @escaping (String) -> [NSRange],
        inlineCodeDelimiterRanges: @escaping (String) -> [NSRange],
        inlineHint: AppTextEditorInlineHint?,
        keyPressKeys: Set<AppTextEditorKey>,
        onKeyPress: @escaping (AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result,
        requestFirstResponder: UUID?,
        onFocusRequestConsumed: @escaping () -> Void,
        isAppKitFirstResponder: Binding<Bool>?,
        disablesAppKitDragDestination: Bool
    ) {
        _text = text
        self.selection = selection
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.placeholder = placeholder
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
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

    var body: some View {
        AppTextInputContainer(
            cornerRadius: cornerRadius,
            cornerRadii: cornerRadii,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: borderWidth
        ) {
            ChatTextEditorRepresentable(
                text: $text,
                selection: selection,
                measuredTextHeight: $measuredTextHeight,
                placeholder: placeholder,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                isDisabled: isDisabled,
                showsDisabledCursor: showsDisabledCursor,
                focus: focus,
                textHighlightRanges: textHighlightRanges,
                textChips: textChips,
                codeBlockRanges: codeBlockRanges,
                inlineCodeBackgroundRanges: inlineCodeBackgroundRanges,
                inlineCodeRanges: inlineCodeRanges,
                inlineCodeDelimiterRanges: inlineCodeDelimiterRanges,
                inlineHint: inlineHint,
                keyPressKeys: keyPressKeys,
                onKeyPress: onKeyPress,
                requestFirstResponder: requestFirstResponder,
                onFocusRequestConsumed: onFocusRequestConsumed,
                isAppKitFirstResponder: isAppKitFirstResponder,
                disablesAppKitDragDestination: disablesAppKitDragDestination
            )
            .frame(
                maxWidth: .infinity,
                minHeight: resolvedHeight,
                idealHeight: resolvedHeight,
                maxHeight: resolvedHeight,
                alignment: .topLeading
            )
            .onChange(of: text) { _, newText in
                primeMeasuredHeightForProgrammaticText(newText)
            }
            .onAppear {
                primeMeasuredHeightForProgrammaticText(text)
            }
        }
    }
}

extension ChatTextEditor {
    private func primeMeasuredHeightForProgrammaticText(_ text: String) {
        measuredTextHeight = Self.primedMeasuredHeight(
            for: text,
            minHeight: minHeight,
            verticalPadding: verticalPadding
        )
    }

    private var resolvedHeight: CGFloat {
        let unclampedHeight = max(measuredTextHeight, idealHeight ?? minHeight)
        if let maxHeight {
            return min(unclampedHeight, maxHeight)
        }
        return unclampedHeight
    }

    static func primedMeasuredHeight(
        for text: String,
        minHeight: CGFloat,
        verticalPadding: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty else {
            return minHeight
        }

        // Programmatic draft restores can run before AppKit has a useful width,
        // so seed height from explicit lines using the same font metrics as the
        // native NSTextView. Hard-coded line heights leave visible empty space
        // inside the composer until AppKit's measured height catches up.
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let lineHeight = primedLineHeight
        let plainTextHeight = CGFloat(max(lineCount, 1)) * lineHeight + (verticalPadding * 2)
        let codeBlockHeight = primedCodeBlockMeasuredHeight(
            for: text,
            lineHeight: lineHeight,
            verticalPadding: verticalPadding
        )
        guard codeBlockHeight <= 0 else {
            return max(minHeight, codeBlockHeight)
        }
        return max(minHeight, plainTextHeight)
    }

    static var primedLineHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(NSLayoutManager().defaultLineHeight(for: font))
    }

    private static func primedCodeBlockMeasuredHeight(
        for text: String,
        lineHeight: CGFloat,
        verticalPadding: CGFloat
    ) -> CGFloat {
        let blocks = AppMarkdownCodeBlockParser.blockCodeRanges(in: text)
        guard !blocks.isEmpty else {
            return 0
        }

        let source = text as NSString
        var visibleLineCount = 0
        var totalBlockHeight: CGFloat = 0
        var currentLocation = 0

        // `primedMeasuredHeight` runs before AppKit has reliable width/layout
        // data. Estimate visible lines only: hidden fence delimiters should not
        // inflate the composer, but code-block chrome and outer gaps should.
        for block in blocks {
            if block.fullRange.location > currentLocation {
                visibleLineCount += primedLineCount(
                    in: source.substring(with: NSRange(location: currentLocation, length: block.fullRange.location - currentLocation))
                )
            }

            let codeLineCount = max(primedLineCount(in: source.substring(with: block.contentRange)), 1)
            totalBlockHeight += CGFloat(codeLineCount) * lineHeight
            totalBlockHeight += AppTextEditorCodeBlockStyling.codeBlockVerticalPadding * 2
            totalBlockHeight += AppTextEditorCodeBlockStyling.codeBlockOuterGap * 2
            currentLocation = NSMaxRange(block.fullRange)
        }

        if currentLocation < source.length {
            visibleLineCount += primedLineCount(
                in: source.substring(with: NSRange(location: currentLocation, length: source.length - currentLocation))
            )
        } else if let lastBlock = blocks.last,
                  lastBlock.delimiterRanges.count > 1,
                  source.length > 0,
                  source.character(at: source.length - 1) == 0x0A {
            visibleLineCount += 1
        }

        return (CGFloat(visibleLineCount) * lineHeight) +
            totalBlockHeight +
            (verticalPadding * 2)
    }

    private static func primedLineCount(in text: String) -> Int {
        let visibleText = text.trimmingCharacters(in: .newlines)
        guard !visibleText.isEmpty else {
            return 0
        }

        return visibleText.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

private struct ChatTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let selection: Binding<TextSelection?>?
    @Binding var measuredTextHeight: CGFloat
    let placeholder: String
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let isDisabled: Bool
    let showsDisabledCursor: Bool
    let focus: FocusState<Bool>.Binding?
    let textHighlightRanges: (String) -> [NSRange]
    let textChips: (String) -> [AppTextEditorChip]
    let codeBlockRanges: (String) -> [NSRange]
    let inlineCodeBackgroundRanges: (String) -> [NSRange]
    let inlineCodeRanges: (String) -> [NSRange]
    let inlineCodeDelimiterRanges: (String) -> [NSRange]
    let inlineHint: AppTextEditorInlineHint?
    let keyPressKeys: Set<AppTextEditorKey>
    let onKeyPress: (AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result
    let requestFirstResponder: UUID?
    let onFocusRequestConsumed: () -> Void
    let isAppKitFirstResponder: Binding<Bool>?
    let disablesAppKitDragDestination: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> ChatTextEditorView {
        let view = ChatTextEditorView(frame: .zero)
        view.configure(configuration)
        return view
    }

    func updateNSView(_ view: ChatTextEditorView, context: Context) {
        view.configure(configuration)
    }
}

private extension ChatTextEditorRepresentable {
    var configuration: ChatTextEditorConfiguration {
        ChatTextEditorConfiguration(
            text: text,
            selectedRange: nsRange(for: selection?.wrappedValue, in: text),
            placeholder: placeholder,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            isDisabled: isDisabled,
            showsDisabledCursor: showsDisabledCursor,
            colorScheme: colorScheme,
            textHighlightRanges: textHighlightRanges,
            textChips: textChips,
            codeBlockRanges: codeBlockRanges,
            inlineCodeBackgroundRanges: inlineCodeBackgroundRanges,
            inlineCodeRanges: inlineCodeRanges,
            inlineCodeDelimiterRanges: inlineCodeDelimiterRanges,
            inlineHint: inlineHint,
            keyPressKeys: keyPressKeys,
            wantsFirstResponder: focus?.wrappedValue == true,
            requestFirstResponder: requestFirstResponder,
            disablesAppKitDragDestination: disablesAppKitDragDestination,
            onTextChange: { newText in
                text = newText
            },
            onSelectionChange: { range in
                guard let selection else {
                    return
                }
                selection.wrappedValue = textSelection(for: range, in: text)
            },
            onMeasuredHeightChange: { height in
                measuredTextHeight = height
            },
            onFocusChange: { isFocused in
                isAppKitFirstResponder?.wrappedValue = isFocused
                guard let focus, focus.wrappedValue != isFocused else {
                    return
                }
                focus.wrappedValue = isFocused
            },
            onKeyPress: onKeyPress,
            onFocusRequestConsumed: onFocusRequestConsumed
        )
    }

    func textSelection(for range: NSRange, in text: String) -> TextSelection? {
        guard let stringRange = Range(range, in: text) else {
            return nil
        }

        if range.length == 0 {
            return TextSelection(insertionPoint: stringRange.lowerBound)
        }
        return TextSelection(range: stringRange)
    }

    func nsRange(for selection: TextSelection?, in text: String) -> NSRange? {
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

    func nsRange(for range: Range<String.Index>, in text: String) -> NSRange? {
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
