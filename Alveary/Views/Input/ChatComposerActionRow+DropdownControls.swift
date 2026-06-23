import AppKit

extension ChatComposerActionRowView {
    func applyPlusButtonConfiguration(_ configuration: Configuration) {
        plusButton.configure(
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.togglePlusMenu()
            }
        )
        reasoningButton.configure(
            selection: configuration.reasoning.selection,
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            showsProgress: configuration.isReconfiguringSession,
            actionHandler: { [weak self] in
                self?.toggleReasoningMenu()
            }
        )
        if !configuration.supportedPermissionModes.isEmpty {
            let permissionOption = selectedPermissionOption(for: configuration)
            permissionButton.configure(
                option: permissionOption,
                height: Self.defaultSettingsControlHeight,
                isEnabled: !configuration.areControlsDisabled,
                actionHandler: { [weak self] in
                    self?.togglePermissionMenu()
                }
            )
            let overrideTooltip = permissionOverrideTooltip(for: configuration)
            permissionButton.toolTip = overrideTooltip
            if let overrideTooltip {
                permissionButton.setAccessibilityValue("\(permissionOption.title). \(overrideTooltip)")
            }
        }
        applyModeChipConfiguration(configuration)
        // Keep open popovers tied to the persisted provider/model/effort and
        // permission state, including async reconfigure rollback updates.
        reasoningMenuController?.update(configuration: configuration.reasoning)
        permissionMenuController?.update(
            options: configuration.supportedPermissionModes,
            selectedValue: configuration.selectedPermissionMode
        )
    }

    func applyModeChipConfiguration(_ configuration: Configuration) {
        planModeButton.configure(
            presentation: .init(title: "Plan", symbolName: "checklist"),
            accessibilityLabel: "Exit plan mode",
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.configuration?.onPlanModeChange(false)
            }
        )
        goalModeButton.configure(
            presentation: .init(title: "Goal", symbolName: "target"),
            accessibilityLabel: "Disable goal mode",
            height: Self.defaultSettingsControlHeight,
            isEnabled: configuration.isGoalModeChipEnabled && !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.configuration?.onGoalModeChipDismiss()
            }
        )
    }

    func selectedPermissionOption(for configuration: Configuration) -> PermissionOptionPresentation {
        if let option = configuration.supportedPermissionModes.first(where: { $0.value == configuration.selectedPermissionMode }) {
            return option
        }
        let providerID = configuration.reasoning.selection.providerID
        return PermissionOptionPresentation(
            value: configuration.selectedPermissionMode,
            title: ChatComposerTextSupport.permissionModeLabel(for: configuration.selectedPermissionMode),
            description: "",
            symbolName: ChatComposerPermissionPresentation.symbolName(
                providerID: providerID,
                value: configuration.selectedPermissionMode
            ),
            isWarning: ChatComposerPermissionPresentation.isWarning(
                providerID: providerID,
                value: configuration.selectedPermissionMode
            )
        )
    }

    func permissionOverrideTooltip(for configuration: Configuration) -> String? {
        guard configuration.reasoning.selection.providerID == "claude",
              configuration.isPlanModeEnabled,
              configuration.selectedPermissionMode == "bypassPermissions" else {
            return nil
        }
        return "Plan mode is active, so Claude still asks for permission until Plan is turned off."
    }
}
