import SwiftUI

struct AppTextEditorChip: Equatable, Sendable {
    let range: NSRange
    let displayText: String
    let style: AppTextEditorChipStyle
}

enum AppTextEditorChipStyle: Equatable, Sendable {
    case slashCommand
    case fileMention
}

struct AppTextEditor: View {
    @Binding private var text: String
    @State private var measuredTextHeight: CGFloat = 0

    private let selection: Binding<TextSelection?>?
    private let placeholder: String?
    private let minHeight: CGFloat
    private let idealHeight: CGFloat?
    private let maxHeight: CGFloat?
    private let cornerRadius: CGFloat
    private let cornerRadii: RectangleCornerRadii?
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let backgroundColor: Color
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let isDisabled: Bool
    private let showsDisabledCursor: Bool
    private let sizesToContent: Bool
    private let focus: FocusState<Bool>.Binding?
    private let textHighlightRanges: ((String) -> [NSRange])?
    private let textChips: ((String) -> [AppTextEditorChip])?
    private let codeBlockRanges: ((String) -> [NSRange])?
    private let inlineCodeBackgroundRanges: ((String) -> [NSRange])?
    private let inlineCodeRanges: ((String) -> [NSRange])?
    private let inlineCodeDelimiterRanges: ((String) -> [NSRange])?
    private let inlineHint: AppTextEditorInlineHint?
    private let keyPressKeys: [AppTextEditorKey]
    private let onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)?
    private let requestFirstResponder: UUID?
    private let onFocusRequestConsumed: (() -> Void)?
    private let isAppKitFirstResponder: Binding<Bool>?
    private let disablesAppKitDragDestination: Bool

    init(
        text: Binding<String>,
        minHeight: CGFloat = 110,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        placeholder: String? = nil,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        cornerRadii: RectangleCornerRadii? = nil,
        horizontalPadding: CGFloat = AppInputStyle.editorHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.editorVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth,
        isDisabled: Bool = false,
        showsDisabledCursor: Bool = false,
        sizesToContent: Bool = false,
        focus: FocusState<Bool>.Binding? = nil,
        textHighlightRanges: ((String) -> [NSRange])? = nil,
        textChips: ((String) -> [AppTextEditorChip])? = nil,
        codeBlockRanges: ((String) -> [NSRange])? = nil,
        inlineCodeBackgroundRanges: ((String) -> [NSRange])? = nil,
        inlineCodeRanges: ((String) -> [NSRange])? = nil,
        inlineCodeDelimiterRanges: ((String) -> [NSRange])? = nil,
        inlineHint: AppTextEditorInlineHint? = nil,
        keyPressKeys: [AppTextEditorKey] = [],
        onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)? = nil,
        requestFirstResponder: UUID? = nil,
        onFocusRequestConsumed: (() -> Void)? = nil,
        isAppKitFirstResponder: Binding<Bool>? = nil,
        disablesAppKitDragDestination: Bool = false
    ) {
        self._text = text
        self.selection = nil
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.isDisabled = isDisabled
        self.showsDisabledCursor = showsDisabledCursor
        self.sizesToContent = sizesToContent
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

    init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        minHeight: CGFloat = 110,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        placeholder: String? = nil,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        cornerRadii: RectangleCornerRadii? = nil,
        horizontalPadding: CGFloat = AppInputStyle.editorHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.editorVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth,
        isDisabled: Bool = false,
        showsDisabledCursor: Bool = false,
        sizesToContent: Bool = false,
        focus: FocusState<Bool>.Binding? = nil,
        textHighlightRanges: ((String) -> [NSRange])? = nil,
        textChips: ((String) -> [AppTextEditorChip])? = nil,
        codeBlockRanges: ((String) -> [NSRange])? = nil,
        inlineCodeBackgroundRanges: ((String) -> [NSRange])? = nil,
        inlineCodeRanges: ((String) -> [NSRange])? = nil,
        inlineCodeDelimiterRanges: ((String) -> [NSRange])? = nil,
        inlineHint: AppTextEditorInlineHint? = nil,
        keyPressKeys: [AppTextEditorKey] = [],
        onKeyPress: ((AppTextEditorKeyPress) -> AppTextEditorKeyPress.Result)? = nil,
        requestFirstResponder: UUID? = nil,
        onFocusRequestConsumed: (() -> Void)? = nil,
        isAppKitFirstResponder: Binding<Bool>? = nil,
        disablesAppKitDragDestination: Bool = false
    ) {
        self._text = text
        self.selection = selection
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.isDisabled = isDisabled
        self.showsDisabledCursor = showsDisabledCursor
        self.sizesToContent = sizesToContent
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
            AppKitTextEditorView(
                text: $text,
                selection: selection,
                measuredTextHeight: $measuredTextHeight,
                reportsMeasuredTextHeight: sizesToContent,
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
                keyPressKeys: Set(keyPressKeys),
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

private extension AppTextEditor {
    func primeMeasuredHeightForProgrammaticText(_ text: String) {
        guard sizesToContent else {
            return
        }

        guard !text.isEmpty else {
            measuredTextHeight = minHeight
            return
        }

        // Binding-driven text replacement can arrive before AppKit has a stable
        // layout width. Prime from explicit lines so the SwiftUI frame can grow
        // immediately, then let AppKit's measured height refine it.
        let estimatedHeight = estimatedHeightFromExplicitLines(in: text)
        if estimatedHeight > measuredTextHeight {
            measuredTextHeight = estimatedHeight
        }
    }

    var resolvedHeight: CGFloat {
        guard sizesToContent else {
            return idealHeight ?? minHeight
        }

        let unclampedHeight = max(measuredTextHeight, minHeight)
        if let maxHeight {
            return min(unclampedHeight, maxHeight)
        }
        return unclampedHeight
    }

    func estimatedHeightFromExplicitLines(in text: String) -> CGFloat {
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return CGFloat(max(lineCount, 1) * 20) + (verticalPadding * 2)
    }
}

struct AppTextInputContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let cornerRadii: RectangleCornerRadii?
    let backgroundColor: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat,
        cornerRadii: RectangleCornerRadii? = nil,
        backgroundColor: Color,
        borderColor: Color,
        borderWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if let cornerRadii {
            content
                .background(
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .fill(backgroundColor)
                )
                .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundColor)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        }
    }
}

/// Single source of truth for Alveary's field and menu chrome, shared by `AppTextField`,
/// `ScheduledTaskMenuPicker`, and `SettingsMenuPicker` so field and menu surfaces
/// cannot drift apart.
enum AppInputStyle {
    static let backgroundOpacity: CGFloat = 0.08
    static let borderOpacity: CGFloat = 0.2
    static let menuBackgroundOpacity: CGFloat = 0.14

    static let backgroundColor = Color.secondary.opacity(backgroundOpacity)
    static let borderColor = Color.secondary.opacity(borderOpacity)
    static let menuBackgroundColor = Color.secondary.opacity(menuBackgroundOpacity)
    static let borderWidth: CGFloat = 1
    static let defaultCornerRadius: CGFloat = AppCornerRadius.standard
    static let defaultHorizontalPadding: CGFloat = 14
    static let defaultVerticalPadding: CGFloat = 10
    static let editorHorizontalPadding: CGFloat = 10
    static let editorVerticalPadding: CGFloat = 8
    static let menuHorizontalPadding: CGFloat = 12
    static let menuChevronPointSize: CGFloat = 11
}
