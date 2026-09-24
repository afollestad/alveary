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

    /// A schedule always pins a whole agent, so there is no inherit row. Checking covers only the first harness load,
    /// since every pane open refreshes and would otherwise blank the selector.
    func agentPresentation(for draft: ScheduledTaskEditorDraft) -> AgentReasoningPresentation {
        let harness = agentHarness(for: draft.harnessID, draft: draft)
        let model = AgentModelOptionSelection.storedModelValue(in: harness.modelOptions, matching: draft.modelSelection)
        return AgentReasoningPresentation(
            harnesses: editorHarnessIDs(for: draft).map { agentHarness(for: $0, draft: draft) },
            pins: .init(harnessID: draft.harnessID, model: model, effort: draft.effort),
            effective: .init(harness: harness, model: model, effort: draft.effort),
            isChecking: isLoadingHarnesses && harnessStatuses.isEmpty
        )
    }

    /// Normalizes after storing so a harness switch also resets a permission mode the new harness lacks.
    func applyAgent(_ pins: AgentReasoningPins, to draft: inout ScheduledTaskEditorDraft) -> Bool {
        guard let harnessID = pins.harnessID, let model = pins.model, let effort = pins.effort else {
            return false
        }
        draft.harnessID = harnessID
        draft.modelSelection = AgentModelOptionSelection.pickerValue(in: modelOptions(for: harnessID, draft: draft), matching: model)
        draft.effort = effort
        normalizeHarnessDependentFields(&draft, explicitSelectionChange: true)
        return true
    }

    /// Discovery and unrelated edits must preserve native selections so preflight can explain unavailable variants.
    func normalizeHarnessDependentFields(_ draft: inout ScheduledTaskEditorDraft, explicitSelectionChange: Bool = false) {
        guard draft.harnessID != "opencode" || explicitSelectionChange else { return }
        let catalog = modelOptions(for: draft.harnessID, draft: draft)
        let offeredModels = AgentModelOptionSelection.menuItems(
            in: catalog,
            selectedModel: nil,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map(\.value)
        if !offeredModels.contains(draft.modelSelection) {
            // Resolve the harness's own default rather than taking the first row: a harness is free to list its
            // strongest model first, and falling into that would silently upgrade the task's cost on a harness switch.
            draft.modelSelection = AgentModelOptionSelection.pickerValue(in: catalog, matching: AppSettings.defaultModelValue)
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

    private func agentHarness(for harnessID: String, draft: ScheduledTaskEditorDraft) -> AgentReasoningPresentation.Harness {
        .init(id: harnessID, title: harnessDisplayName(for: harnessID), modelOptions: modelOptions(for: harnessID, draft: draft))
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
