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
            permissionButton.configure(
                option: selectedPermissionOption(for: configuration),
                height: Self.defaultSettingsControlHeight,
                isEnabled: !configuration.areControlsDisabled,
                actionHandler: { [weak self] in
                    self?.togglePermissionMenu()
                }
            )
        }
        // Keep open popovers tied to the persisted provider/model/effort and
        // permission state, including async reconfigure rollback updates.
        reasoningMenuController?.update(configuration: configuration.reasoning)
        permissionMenuController?.update(
            options: configuration.supportedPermissionModes,
            selectedValue: configuration.selectedPermissionMode
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
}
