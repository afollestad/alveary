import SwiftUI

struct AppTextField: View {
    @Binding private var text: String

    private let title: String
    private let cornerRadius: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let backgroundColor: Color
    private let borderColor: Color
    private let borderWidth: CGFloat

    init(
        _ title: String,
        text: Binding<String>,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        horizontalPadding: CGFloat = AppInputStyle.defaultHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.defaultVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth
    ) {
        self._text = text
        self.title = title
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    var body: some View {
        AppTextInputContainer(
            cornerRadius: cornerRadius,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: borderWidth
        ) {
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppTextEditor: View {
    @Binding private var text: String

    private let selection: Binding<TextSelection?>?
    private let minHeight: CGFloat
    private let maxHeight: CGFloat?
    private let cornerRadius: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let backgroundColor: Color
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let isDisabled: Bool
    private let focus: FocusState<Bool>.Binding?
    private let keyPressKeys: [KeyEquivalent]
    private let onKeyPress: ((KeyPress) -> KeyPress.Result)?

    init(
        text: Binding<String>,
        minHeight: CGFloat = 110,
        maxHeight: CGFloat? = nil,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        horizontalPadding: CGFloat = AppInputStyle.editorHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.editorVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth,
        isDisabled: Bool = false,
        focus: FocusState<Bool>.Binding? = nil,
        keyPressKeys: [KeyEquivalent] = [],
        onKeyPress: ((KeyPress) -> KeyPress.Result)? = nil
    ) {
        self._text = text
        self.selection = nil
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.isDisabled = isDisabled
        self.focus = focus
        self.keyPressKeys = keyPressKeys
        self.onKeyPress = onKeyPress
    }

    init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        minHeight: CGFloat = 110,
        maxHeight: CGFloat? = nil,
        cornerRadius: CGFloat = AppInputStyle.defaultCornerRadius,
        horizontalPadding: CGFloat = AppInputStyle.editorHorizontalPadding,
        verticalPadding: CGFloat = AppInputStyle.editorVerticalPadding,
        backgroundColor: Color = AppInputStyle.backgroundColor,
        borderColor: Color = AppInputStyle.borderColor,
        borderWidth: CGFloat = AppInputStyle.borderWidth,
        isDisabled: Bool = false,
        focus: FocusState<Bool>.Binding? = nil,
        keyPressKeys: [KeyEquivalent] = [],
        onKeyPress: ((KeyPress) -> KeyPress.Result)? = nil
    ) {
        self._text = text
        self.selection = selection
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.isDisabled = isDisabled
        self.focus = focus
        self.keyPressKeys = keyPressKeys
        self.onKeyPress = onKeyPress
    }

    var body: some View {
        AppTextInputContainer(
            cornerRadius: cornerRadius,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: borderWidth
        ) {
            editorContent
        }
    }
}

private extension AppTextEditor {
    @ViewBuilder
    var editorContent: some View {
        if let selection {
            configuredEditor(TextEditor(text: $text, selection: selection))
        } else {
            configuredEditor(TextEditor(text: $text))
        }
    }

    @ViewBuilder
    func configuredEditor<Editor: View>(_ editor: Editor) -> some View {
        if let focus {
            if let onKeyPress, !keyPressKeys.isEmpty {
                editor
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(isDisabled)
                    .focused(focus)
                    .onKeyPress(keys: Set(keyPressKeys), action: onKeyPress)
            } else {
                editor
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(isDisabled)
                    .focused(focus)
            }
        } else if let onKeyPress, !keyPressKeys.isEmpty {
            editor
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(isDisabled)
                .onKeyPress(keys: Set(keyPressKeys), action: onKeyPress)
        } else {
            editor
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(isDisabled)
        }
    }
}

private struct AppTextInputContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let backgroundColor: Color
    let borderColor: Color
    let borderWidth: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat,
        backgroundColor: Color,
        borderColor: Color,
        borderWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content()
    }

    var body: some View {
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

private enum AppInputStyle {
    static let backgroundColor = Color.secondary.opacity(0.08)
    static let borderColor = Color.secondary.opacity(0.2)
    static let borderWidth: CGFloat = 1
    static let defaultCornerRadius: CGFloat = 12
    static let defaultHorizontalPadding: CGFloat = 14
    static let defaultVerticalPadding: CGFloat = 10
    static let editorHorizontalPadding: CGFloat = 10
    static let editorVerticalPadding: CGFloat = 8
}
