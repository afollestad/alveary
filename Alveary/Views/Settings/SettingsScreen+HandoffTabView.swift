import SwiftUI

struct HandoffSettingsTabView: View {
    @Binding var contextManagementEnabled: Bool
    @Binding var sessionHandoffWindowPercentage: Int
    @Binding var handoffSteeringEnabled: Bool
    @Binding var handoffSteeringCountdownSeconds: Int
    @Binding var handoffPromptSendCountdownSeconds: Int
    @Binding var handoffContextCustomizationEnabled: Bool
    @Binding var sessionHandoffPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsScreenLayout.settingsSectionSpacing) {
            SettingsFormSection {
                SettingsToggleRow(
                    "Enable automatic session handoff",
                    helpText: ContextManagementHelp.contextManagementEnabled,
                    isOn: $contextManagementEnabled
                )

                SettingsFormRow {
                    SettingsResponsiveControlRow(
                        "Session handoff window percentage",
                        helpText: ContextManagementHelp.sessionHandoffWindowPercentage,
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsValueStepper(
                            "Session handoff window percentage",
                            value: $sessionHandoffWindowPercentage,
                            in: AppSettings.supportedHandoffPercentageRange,
                            step: AppSettings.sessionHandoffWindowPercentageStep,
                            unit: "%",
                            unitSeparator: "",
                            accessibilityUnit: "percent"
                        )
                    }
                }
                .disabled(!contextManagementEnabled)

                SettingsPromptEditorRow(
                    "Default session handoff prompt",
                    helpText: ContextManagementHelp.defaultSessionHandoffPrompt,
                    prompt: $sessionHandoffPrompt,
                    defaultPrompt: AppSettings.defaultSessionHandoffPrompt,
                    placeholder: "Write the prompt used to prepare a session handoff."
                )

                SettingsToggleRow(
                    "Enable handoff steering",
                    helpText: ContextManagementHelp.handoffSteeringEnabled,
                    isOn: $handoffSteeringEnabled,
                    isDisabled: !contextManagementEnabled
                )

                SettingsFormRow {
                    SettingsResponsiveControlRow(
                        "Handoff steering countdown",
                        helpText: ContextManagementHelp.handoffSteeringCountdown,
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsValueStepper(
                            "Handoff steering countdown",
                            value: $handoffSteeringCountdownSeconds,
                            in: AppSettings.supportedHandoffSteeringCountdownRange,
                            unit: "s",
                            unitSeparator: "",
                            accessibilityUnit: "seconds"
                        )
                    }
                }
                .disabled(!contextManagementEnabled || !handoffSteeringEnabled)

                SettingsToggleRow(
                    "Allow handoff context customization",
                    helpText: ContextManagementHelp.handoffContextCustomization,
                    isOn: $handoffContextCustomizationEnabled
                )

                SettingsFormRow(showsDivider: false) {
                    SettingsResponsiveControlRow(
                        "Handoff prompt send countdown",
                        helpText: ContextManagementHelp.handoffPromptSendCountdown,
                        horizontalControlSizing: .intrinsic
                    ) {
                        SettingsValueStepper(
                            "Handoff prompt send countdown",
                            value: $handoffPromptSendCountdownSeconds,
                            in: AppSettings.supportedHandoffPromptSendCountdownRange,
                            unit: "s",
                            unitSeparator: "",
                            accessibilityUnit: "seconds"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ContextManagementHelp {
    static let contextManagementEnabled =
        "Automatically starts session handoff when the context window crosses the configured threshold."
    static let sessionHandoffWindowPercentage =
        "Triggers session handoff when the context window reaches this percentage."
    static let defaultSessionHandoffPrompt =
        "Prompt sent to the agent to collect context for the next session."
    static let handoffSteeringEnabled =
        "Lets you steer the handoff output when automatic session handoff starts."
    static let handoffSteeringCountdown =
        "Seconds to enter steering before continuing with the default handoff. " +
        "The countdown stops when you start typing in the composer."
    static let handoffContextCustomization =
        "Lets you edit the generated handoff context before it is sent to the next session. " +
        "This happens after steering."
    static let handoffPromptSendCountdown =
        "Seconds to edit generated handoff context before it is sent automatically to the next session. " +
        "The countdown stops when you start typing in the composer."
}
