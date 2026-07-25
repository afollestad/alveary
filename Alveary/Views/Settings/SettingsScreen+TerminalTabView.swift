import SwiftUI

struct TerminalSettingsTabView: View {
    @Binding var expandTerminalWhenActionsRun: Bool
    @Binding var maxTerminalSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow(
                    "Expand terminal when actions run",
                    isOn: $expandTerminalWhenActionsRun
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow("Max terminal sessions", horizontalControlSizing: .intrinsic) {
                        SettingsValueStepper(
                            "Max terminal sessions",
                            value: $maxTerminalSessions,
                            in: AppSettings.supportedMaxTerminalSessionsRange,
                            unit: "",
                            accessibilityUnit: "sessions"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
