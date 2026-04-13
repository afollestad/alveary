import SwiftUI

enum SettingsScreenLayout {
    static let settingsRowHeight: CGFloat = 32
    static let settingsTextFieldWidth: CGFloat = 320
}

struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String

    private let width: CGFloat
    private let textAlignment: TextAlignment

    init(
        _ title: String,
        text: Binding<String>,
        width: CGFloat = SettingsScreenLayout.settingsTextFieldWidth,
        textAlignment: TextAlignment = .trailing
    ) {
        self.title = title
        _text = text
        self.width = width
        self.textAlignment = textAlignment
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .accessibilityHidden(true)

            Spacer(minLength: 16)

            AppTextField(
                title,
                text: $text,
                showsPrompt: false,
                textAlignment: textAlignment,
                horizontalPadding: 10,
                verticalPadding: 7
            )
            .frame(width: width)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
    }
}
