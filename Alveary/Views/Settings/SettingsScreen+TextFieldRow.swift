import SwiftUI

enum SettingsScreenLayout {
    static let settingsRowHeight: CGFloat = 32
    static let settingsControlWidthFraction: CGFloat = 0.5
    static let settingsMinimumHorizontalControlWidth: CGFloat = 180
    static let settingsResponsiveRowSpacing: CGFloat = 12
    static let settingsResponsiveStackedSpacing: CGFloat = 8
    static let settingsRowHorizontalPadding: CGFloat = 20
    static let settingsRowVerticalPadding: CGFloat = 12
    static let settingsRowPressedOpacity: CGFloat = 0.03
    static let settingsControlSurfaceHeight: CGFloat = 36
    static let settingsPickerWidth: CGFloat = 150
    static let settingsValueStepperWidth: CGFloat = 150
    static let settingsSectionCornerRadius: CGFloat = 18
    static let settingsSectionSpacing: CGFloat = 28
    static let settingsSectionHeaderSpacing: CGFloat = 10
}

struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String

    private let textAlignment: TextAlignment

    init(
        _ title: String,
        text: Binding<String>,
        textAlignment: TextAlignment = .trailing
    ) {
        self.title = title
        _text = text
        self.textAlignment = textAlignment
    }

    var body: some View {
        SettingsResponsiveControlRow(title) {
            AppTextField(
                title,
                text: $text,
                showsPrompt: false,
                textAlignment: textAlignment,
                horizontalPadding: 10,
                verticalPadding: 7
            )
        }
    }
}
