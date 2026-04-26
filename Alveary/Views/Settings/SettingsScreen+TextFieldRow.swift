import AppKit
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

    private let horizontalControlSizing: SettingsTextFieldHorizontalSizing
    private let textAlignment: TextAlignment

    init(
        _ title: String,
        text: Binding<String>,
        horizontalControlSizing: SettingsTextFieldHorizontalSizing = .fillsAvailableWidth,
        textAlignment: TextAlignment = .trailing
    ) {
        self.title = title
        _text = text
        self.horizontalControlSizing = horizontalControlSizing
        self.textAlignment = textAlignment
    }

    var body: some View {
        SettingsResponsiveControlRow(title, horizontalControlSizing: responsiveControlSizing) {
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

    private var responsiveControlSizing: SettingsControlHorizontalSizing {
        switch horizontalControlSizing {
        case .fillsAvailableWidth:
            return .fillsAvailableWidth
        case .expandsToFitText:
            return .expandsToFitContent(idealWidth: idealTextFieldWidth)
        }
    }

    private var idealTextFieldWidth: CGFloat {
        let measuredText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !measuredText.isEmpty else {
            return SettingsScreenLayout.settingsPickerWidth
        }
        let textWidth = (measuredText as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]).width
        return ceil(textWidth) + 28
    }
}

enum SettingsTextFieldHorizontalSizing {
    case fillsAvailableWidth
    case expandsToFitText
}
