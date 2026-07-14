import AgentCLIKit
import Foundation

extension ScheduledTasksViewModel {
    var availableProviderIDs: [String] {
        providerResolution.readyProviderIDs
    }

    func providerIDs(including selectedProviderID: String) -> [String] {
        var values = availableProviderIDs
        if !selectedProviderID.isEmpty, !values.contains(selectedProviderID) {
            values.append(selectedProviderID)
        }
        return values
    }

    func providerDisplayName(for providerID: String) -> String {
        providerStatuses[providerID]?.definition?.displayName
            ?? agentRegistry.agent(for: providerID)?.name
            ?? providerID.capitalized
    }

    func modelOptions(for providerID: String) -> [AgentCLIKit.AgentModelOption] {
        ThreadDefaultResolver.modelOptions(for: providerID, providerStatuses: providerStatuses)
    }

    func modelPickerOptions(for providerID: String, including selection: String) -> [ScheduledTaskPickerOption] {
        AgentModelOptionSelection.menuItems(
            in: modelOptions(for: providerID),
            selectedModel: selection,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { ScheduledTaskPickerOption(value: $0.value, label: $0.title) }
    }

    func effortOptions(for providerID: String, modelSelection: String) -> [ScheduledTaskPickerOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: providerID),
            selectedModel: modelSelection
        ).map { ScheduledTaskPickerOption(value: $0.value, label: $0.label) }
    }

    func permissionModeOptions(
        for providerID: String,
        including selection: String? = nil
    ) -> [ScheduledTaskPickerOption] {
        let options: [PermissionModeOption]
        if let supported = providerStatuses[providerID]?.definition?.supportedPermissionModes {
            options = supported
                .filter { $0.value != "plan" }
                .map { PermissionModeOption(value: $0.value, label: $0.label, description: $0.description) }
        } else {
            options = agentRegistry.agent(for: providerID)?.provider?.supportedPermissionModes?
                .filter { $0.value != "plan" } ?? []
        }
        var pickerOptions = options.map {
            ScheduledTaskPickerOption(
                value: $0.value,
                label: ChatComposerTextSupport.permissionModeLabel(for: $0)
            )
        }
        if let selection,
           !selection.isEmpty,
           !pickerOptions.contains(where: { $0.value == selection }) {
            pickerOptions.append(ScheduledTaskPickerOption(
                value: selection,
                label: ChatComposerTextSupport.permissionModeLabel(for: selection)
            ))
        }
        return pickerOptions
    }

    func normalizeProviderDependentFields(_ draft: inout ScheduledTaskEditorDraft) {
        let modelOptions = modelPickerOptions(for: draft.providerID, including: AppSettings.defaultModelValue)
        if !modelOptions.contains(where: { $0.value == draft.modelSelection }) {
            draft.modelSelection = modelOptions.first?.value ?? AppSettings.defaultModelValue
        }

        let effortOptions = effortOptions(for: draft.providerID, modelSelection: draft.modelSelection)
        if !effortOptions.contains(where: { $0.value == draft.effort }) {
            draft.effort = effortOptions.first?.value ?? AppSettings.defaultEffortLevel
        }

        let permissionOptions = permissionModeOptions(for: draft.providerID)
        if !permissionOptions.contains(where: { $0.value == draft.permissionMode }) {
            let defaultPermissionMode = AppSettings.defaultPermissionMode(forProvider: draft.providerID)
            draft.permissionMode = permissionOptions.first(where: { $0.value == defaultPermissionMode })?.value
                ?? permissionOptions.first?.value
                ?? defaultPermissionMode
        }
    }

    func refreshProviders() async {
        guard let providerDiscovery else {
            providerStatuses = [:]
            providerOrdering = AppSettings.supportedProviderIDs
            return
        }

        isLoadingProviders = true
        async let ordering = providerDiscovery.stableProviderOrdering()
        async let statuses = providerDiscovery.providerStatuses(projectURL: nil)
        let (resolvedOrdering, resolvedStatuses) = await (ordering, statuses)
        providerOrdering = resolvedOrdering.map(\.rawValue)
        providerStatuses = Dictionary(
            uniqueKeysWithValues: resolvedStatuses.map { ($0.key.rawValue, $0.value) }
        )
        isLoadingProviders = false
    }
}

extension ScheduledTasksViewModel {
    var providerResolution: ThreadDefaultResolution {
        ThreadDefaultResolver.resolve(
            settings: settingsService.current,
            providerOrdering: providerOrdering,
            providerStatuses: providerStatuses,
            allowStaticFallback: providerDiscovery == nil
        )
    }
}
