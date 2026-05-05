@preconcurrency import AppKit
import SwiftUI

/// Renderer-neutral configuration for the native composer text editor.
///
/// SwiftUI wrappers and future native composer surfaces pass this value into
/// `ChatTextEditorView`, keeping chip styling, key handling, and focus requests
/// on the same AppKit editor path.
struct ChatTextEditorConfiguration {
    var text: String
    var selectedRange: NSRange?
    var placeholder: String
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var isDisabled: Bool
    var showsDisabledCursor: Bool
    var colorScheme: ColorScheme
    var textHighlightRanges: (String) -> [NSRange]
    var textChips: (String) -> [AppTextEditorChip]
    var codeBlockRanges: (String) -> [NSRange]
    var inlineCodeBackgroundRanges: (String) -> [NSRange]
    var inlineCodeRanges: (String) -> [NSRange]
    var inlineCodeDelimiterRanges: (String) -> [NSRange]
    var inlineHint: AppTextEditorInlineHint?
    var keyPressKeys: Set<AppTextEditorKey>
    var wantsFirstResponder: Bool
    var requestFirstResponder: UUID?
    var disablesAppKitDragDestination: Bool
    var onTextChange: (String) -> Void
    var onSelectionChange: (NSRange) -> Void
    var onMeasuredHeightChange: (CGFloat) -> Void
    var onFocusChange: (Bool) -> Void
    var onKeyPress: (AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result
    var onFocusRequestConsumed: () -> Void

    init(
        text: String,
        selectedRange: NSRange? = nil,
        placeholder: String = "",
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 10,
        isDisabled: Bool = false,
        showsDisabledCursor: Bool = false,
        colorScheme: ColorScheme = .light,
        textHighlightRanges: @escaping (String) -> [NSRange] = { _ in [] },
        textChips: @escaping (String) -> [AppTextEditorChip] = { _ in [] },
        codeBlockRanges: @escaping (String) -> [NSRange] = { _ in [] },
        inlineCodeBackgroundRanges: @escaping (String) -> [NSRange] = { _ in [] },
        inlineCodeRanges: @escaping (String) -> [NSRange] = { _ in [] },
        inlineCodeDelimiterRanges: @escaping (String) -> [NSRange] = { _ in [] },
        inlineHint: AppTextEditorInlineHint? = nil,
        keyPressKeys: Set<AppTextEditorKey> = [],
        wantsFirstResponder: Bool = false,
        requestFirstResponder: UUID? = nil,
        disablesAppKitDragDestination: Bool = false,
        onTextChange: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (NSRange) -> Void = { _ in },
        onMeasuredHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        onKeyPress: @escaping (AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result = { _ in .ignored },
        onFocusRequestConsumed: @escaping () -> Void = {}
    ) {
        self.text = text
        self.selectedRange = selectedRange
        self.placeholder = placeholder
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isDisabled = isDisabled
        self.showsDisabledCursor = showsDisabledCursor
        self.colorScheme = colorScheme
        self.textHighlightRanges = textHighlightRanges
        self.textChips = textChips
        self.codeBlockRanges = codeBlockRanges
        self.inlineCodeBackgroundRanges = inlineCodeBackgroundRanges
        self.inlineCodeRanges = inlineCodeRanges
        self.inlineCodeDelimiterRanges = inlineCodeDelimiterRanges
        self.inlineHint = inlineHint
        self.keyPressKeys = keyPressKeys
        self.wantsFirstResponder = wantsFirstResponder
        self.requestFirstResponder = requestFirstResponder
        self.disablesAppKitDragDestination = disablesAppKitDragDestination
        self.onTextChange = onTextChange
        self.onSelectionChange = onSelectionChange
        self.onMeasuredHeightChange = onMeasuredHeightChange
        self.onFocusChange = onFocusChange
        self.onKeyPress = onKeyPress
        self.onFocusRequestConsumed = onFocusRequestConsumed
    }
}
