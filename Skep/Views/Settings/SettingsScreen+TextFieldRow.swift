import SwiftUI

enum SettingsScreenLayout {
    static let settingsRowHeight: CGFloat = 32
    static let settingsTextFieldWidth: CGFloat = 320
}

struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
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
                textAlignment: .trailing,
                horizontalPadding: 10,
                verticalPadding: 7
            )
            .frame(width: SettingsScreenLayout.settingsTextFieldWidth)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsScreenLayout.settingsRowHeight, alignment: .leading)
    }
}
