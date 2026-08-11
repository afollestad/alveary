import SwiftUI

struct MenuBarSettingsTabView: View {
    @Binding var showsMenuBarIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow(
                    "Show menu bar icon",
                    helpText: "Adds an Alveary icon to the system menu bar for recent threads and quick actions.",
                    isOn: $showsMenuBarIcon,
                    showsDivider: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
