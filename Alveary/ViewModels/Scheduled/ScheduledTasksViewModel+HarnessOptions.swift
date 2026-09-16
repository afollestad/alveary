import AgentCLIKit
import Foundation

extension ScheduledTasksViewModel {
    var availableHarnessIDs: [String] {
        harnessResolution.readyHarnessIDs
    }

    func harnessIDs(including selectedHarnessID: String) -> [String] {
        var values = availableHarnessIDs
        if !selectedHarnessID.isEmpty, !values.contains(selectedHarnessID) {
            values.append(selectedHarnessID)
        }
        return values
    }

    func harnessDisplayName(for harnessID: String) -> String {
        harnessStatuses[harnessID]?.definition?.displayName
            ?? agentRegistry.agent(for: harnessID)?.name
            ?? harnessID.capitalized
    }

    func modelOptions(for harnessID: String, draft: ScheduledTaskEditorDraft? = nil) -> [AgentCLIKit.AgentModelOption] {
        if harnessID == "opencode", let draft, harnessDiscovery != nil,
           let directory = openCodeDiscoveryDirectory(for: draft) {
            if case .loaded(let status) = openCodeEditorCatalogs[directory], let status {
                return status.modelOptions
            }
            return AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: .opencode)
        }
        return ThreadDefaultResolver.modelOptions(for: harnessID, harnessStatuses: harnessStatuses)
    }

    func modelPickerOptions(
        for harnessID: String, including selection: String, draft: ScheduledTaskEditorDraft? = nil
    ) -> [ScheduledTaskPickerOption] {
        AgentModelOptionSelection.menuItems(
            in: modelOptions(for: harnessID, draft: draft),
            selectedModel: selection,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { ScheduledTaskPickerOption(value: $0.value, label: $0.title) }
    }

    func effortOptions(
        for harnessID: String, modelSelection: String, draft: ScheduledTaskEditorDraft? = nil
    ) -> [ScheduledTaskPickerOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: harnessID, draft: draft),
            selectedModel: modelSelection
        ).map { ScheduledTaskPickerOption(value: $0.value, label: $0.label) }
    }

    func permissionModeOptions(
        for harnessID: String,
        including selection: String? = nil
    ) -> [ScheduledTaskPickerOption] {
        let options: [PermissionModeOption]
        if let supported = harnessStatuses[harnessID]?.definition?.supportedPermissionModes {
            options = supported
                .filter { $0.value != "plan" }
                .map { PermissionModeOption(value: $0.value, label: $0.label, description: $0.description) }
        } else {
            options = agentRegistry.agent(for: harnessID)?.harness?.supportedPermissionModes?
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

    /// Discovery and unrelated edits must preserve native selections so preflight can explain unavailable variants.
    func normalizeHarnessDependentFields(_ draft: inout ScheduledTaskEditorDraft, explicitSelectionChange: Bool = false) {
        guard draft.harnessID != "opencode" || explicitSelectionChange else { return }
        let modelOptions = modelPickerOptions(for: draft.harnessID, including: AppSettings.defaultModelValue, draft: draft)
        if !modelOptions.contains(where: { $0.value == draft.modelSelection }) {
            // Resolve the harness's own default rather than taking the first row: a harness is free to list its
            // strongest model first, and falling into that would silently upgrade the task's cost on a harness switch.
            draft.modelSelection = AgentModelOptionSelection.pickerValue(
                in: self.modelOptions(for: draft.harnessID, draft: draft),
                matching: AppSettings.defaultModelValue
            )
        }

        let effortOptions = effortOptions(for: draft.harnessID, modelSelection: draft.modelSelection, draft: draft)
        if !effortOptions.contains(where: { $0.value == draft.effort }) {
            draft.effort = draft.harnessID == "opencode"
                ? AppSettings.openCodeDefaultEffort : effortOptions.first?.value ?? AppSettings.defaultEffortLevel
        }

        let permissionOptions = permissionModeOptions(for: draft.harnessID)
        if !permissionOptions.contains(where: { $0.value == draft.permissionMode }) {
            let defaultPermissionMode = AppSettings.defaultPermissionMode(forHarness: draft.harnessID)
            draft.permissionMode = permissionOptions.first(where: { $0.value == defaultPermissionMode })?.value
                ?? permissionOptions.first?.value
                ?? defaultPermissionMode
        }
    }

    func refreshHarnesses() async {
        guard let harnessDiscovery else {
            harnessStatuses = [:]
            harnessOrdering = AppSettings.supportedHarnessIDs
            return
        }

        isLoadingHarnesses = true
        async let ordering = harnessDiscovery.stableHarnessOrdering()
        async let statuses = harnessDiscovery.harnessStatuses(projectURL: nil)
        let (resolvedOrdering, resolvedStatuses) = await (ordering, statuses)
        harnessOrdering = resolvedOrdering.map(\.rawValue)
        harnessStatuses = Dictionary(
            uniqueKeysWithValues: resolvedStatuses.map { ($0.key.rawValue, $0.value) }
        )
        isLoadingHarnesses = false
    }
}

extension ScheduledTasksViewModel {
    var harnessResolution: ThreadDefaultResolution {
        ThreadDefaultResolver.resolve(
            settings: settingsService.current,
            harnessOrdering: harnessOrdering,
            harnessStatuses: harnessStatuses,
            allowStaticFallback: harnessDiscovery == nil
        )
    }
}
