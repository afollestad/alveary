import AgentCLIKit
import SwiftUI

extension SettingsViewModel {
    var availableHarnessIDs: [String] {
        let ordered = harnessOrdering.isEmpty ? AppSettings.supportedHarnessIDs : harnessOrdering
        let supported = ordered.filter(AppSettings.supportedHarnessIDs.contains)
        return supported.isEmpty ? AppSettings.supportedHarnessIDs : supported
    }

    var isCheckingThreadDefaultHarnesses: Bool {
        harnessDiscovery != nil && !hasLoadedHarnessStatuses
    }

    var threadDefaultHarnessIDs: [String] {
        threadDefaultResolution.readyHarnessIDs
    }

    var hasReadyThreadDefaultHarness: Bool {
        threadDefaultResolution.hasReadyHarness
    }

    var threadDefaultHarnessSelection: String {
        threadDefaultResolution.harnessID ?? settingsService.current.defaultHarness
    }

    var threadDefaultModelSelection: String {
        AgentModelOptionSelection.pickerValue(
            in: threadDefaultResolution.modelOptions,
            matching: threadDefaultResolution.storedThreadModel
        )
    }

    var threadDefaultModelOptionValues: [String] {
        let options = threadDefaultResolution.modelOptions
        let values = options.map(AgentModelOptionSelection.pickerValue(for:))
        return values.isEmpty ? [AppSettings.defaultModelValue] : values
    }

    var threadDefaultPermissionModeOptions: [String] {
        guard let harnessID = threadDefaultResolution.harnessID else {
            return []
        }
        return permissionModeOptions(for: harnessID)
    }

    var threadDefaultEffortOptions: [AgentCLIKit.AgentHarnessOption] {
        AgentModelOptionSelection.effortOptions(
            in: threadDefaultResolution.modelOptions,
            selectedModel: threadDefaultResolution.storedThreadModel
        )
    }

    var supportedModels: [String] {
        modelOptionValues(for: defaultHarness, including: settingsService.current.defaultModel)
    }

    var defaultHarness: String {
        get { settingsService.current.defaultHarness }
        set {
            let options = modelOptions(for: newValue)
            settingsService.update { settings in
                settings.defaultHarness = newValue
                settings.setHarness(newValue, enabled: true)
                if AgentModelOptionSelection.option(in: options, matching: settings.defaultModel) == nil {
                    settings.defaultModel = AppSettings.defaultModelValue
                }
                if !AppSettings.supportedPermissionModes(forHarness: newValue).contains(settings.permissionMode) {
                    settings.permissionMode = AppSettings.defaultPermissionMode(forHarness: newValue)
                }
                settings.effort = AgentModelOptionSelection.normalizedEffort(
                    settings.effort,
                    options: options,
                    selectedModel: settings.defaultModel
                )
            }
        }
    }

    var defaultModel: String {
        get {
            AgentModelOptionSelection.pickerValue(
                in: modelOptions(for: settingsService.current.defaultHarness),
                matching: settingsService.current.defaultModel
            )
        }
        set {
            let options = modelOptions(for: settingsService.current.defaultHarness)
            let storedModel = AgentModelOptionSelection.storedModelValue(in: options, matching: newValue)
            settingsService.update { settings in
                let previousEffort = settings.effort
                settings.defaultModel = storedModel
                let normalizedEffort = AgentModelOptionSelection.normalizedEffort(
                    previousEffort,
                    options: options,
                    selectedModel: storedModel
                )
                settings.effort = previousEffort == AppSettings.defaultEffortLevel
                    ? AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: storedModel)
                    : normalizedEffort
            }
        }
    }

    var permissionMode: String {
        get { settingsService.current.permissionMode }
        set {
            settingsService.update { settings in
                let supportedModes = AppSettings.supportedPermissionModes(forHarness: settings.defaultHarness)
                settings.permissionMode = supportedModes.contains(newValue)
                    ? newValue
                    : AppSettings.defaultPermissionMode(forHarness: settings.defaultHarness)
            }
        }
    }

    func permissionModeOptions(for harnessId: String) -> [String] {
        let metadata = permissionModeOptionMetadata(for: harnessId)
        if !metadata.isEmpty {
            return metadata.map(\.value)
        }
        return AppSettings.supportedPermissionModes(forHarness: harnessId)
    }

    func permissionModeOptionMetadata(for harnessId: String) -> [PermissionModeOption] {
        if let status = harnessStatus(for: harnessId),
           let modes = status.definition?.supportedPermissionModes {
            return modes
                .filter { $0.value != "plan" }
                .map { PermissionModeOption(value: $0.value, label: $0.label, description: $0.description) }
        }
        return (agentRegistry.agent(for: harnessId)?.harness?.supportedPermissionModes ?? [])
            .filter { $0.value != "plan" }
    }

    func permissionModeLabel(for value: String, harnessId: String) -> String {
        if let option = permissionModeOptionMetadata(for: harnessId).first(where: { $0.value == value }) {
            return ChatComposerTextSupport.permissionModeLabel(for: option)
        }
        return ChatComposerTextSupport.permissionModeLabel(for: value)
    }

    func installCommand(for harnessId: String) -> String? {
        agentRegistry.agent(for: harnessId)?.installCommand
    }

    func signInCommand(for harnessId: String) -> String? {
        agentRegistry.agent(for: harnessId)?.signInCommand
    }

    func harnessStatus(for harnessId: String) -> AgentCLIKit.AgentHarnessStatus? {
        if let status = harnessStatuses[harnessId] {
            return status
        }
        guard let id = AgentCLIKit.AgentHarnessID(rawValue: harnessId) else {
            return nil
        }
        return AgentCLIKit.AgentHarnessStatus(
            harnessId: id,
            definition: nil,
            installation: .unknown,
            isEnabled: settingsService.current.isHarnessEnabled(harnessId),
            setup: .unknown,
            modelOptions: AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: id)
        )
    }

    func refreshHarnessStatusesIfNeeded() async {
        guard harnessStatuses.isEmpty else {
            return
        }
        await refreshHarnessStatuses()
    }

    /// Returning from an external install or sign-in repairs visible unavailable harnesses without probing on every app switch when ready.
    func refreshHarnessStatusesAfterActivation() async {
        guard hasLoadedHarnessStatuses,
              harnessStatuses.values.contains(where: {
                  $0.isEnabled && settingsService.current.isHarnessEnabled($0.harnessId.rawValue)
                      && (!$0.isInstalled || !$0.isSetupReady)
              }) else { return }
        await refreshHarnessStatuses()
    }

    func refreshHarnessStatuses() async {
        harnessRefreshGeneration &+= 1
        let generation = harnessRefreshGeneration
        guard let harnessDiscovery else {
            harnessStatuses = [:]
            harnessOrdering = AppSettings.supportedHarnessIDs
            hasLoadedHarnessStatuses = true
            return
        }

        hasLoadedHarnessStatuses = false
        defer {
            if generation == harnessRefreshGeneration { hasLoadedHarnessStatuses = true }
        }
        // Re-probe rather than reading the shared cache: this screen is where a CLI gets
        // installed or a setup completed, so it is the one place staleness would be visible.
        await invalidateHarnessDiscoveryCache()
        guard generation == harnessRefreshGeneration, !Task.isCancelled else { return }
        let ordering = await harnessDiscovery.stableHarnessOrdering().map(\.rawValue)
        let statuses = await harnessDiscovery.harnessStatuses(projectURL: nil)
        guard generation == harnessRefreshGeneration, !Task.isCancelled else { return }

        harnessOrdering = ordering
        harnessStatuses = Dictionary(
            uniqueKeysWithValues: statuses.map { ($0.key.rawValue, $0.value) }
        )
        persistResolvedThreadDefaultsIfNeeded()
    }

    func shortStatusLabel(for status: AgentCLIKit.AgentHarnessStatus?) -> String {
        guard let status else {
            return "Unknown"
        }
        if !status.isEnabled {
            return "Disabled"
        }
        switch status.installation {
        case .missing:
            return "Missing"
        case .unknown:
            return "Checking"
        case .installed:
            return setupStatusLabel(for: status.setup)
        }
    }

    func statusDescription(for status: AgentCLIKit.AgentHarnessStatus?) -> String {
        guard let status else {
            return "Harness is not registered."
        }
        if !status.isEnabled {
            return "Disabled in Alveary settings."
        }
        if let diagnostic = status.diagnostics.first {
            return diagnostic
        }
        switch status.installation {
        case .unknown:
            return "Checking installation status."
        case .missing:
            return "Not installed on this Mac yet."
        case .installed:
            return installedStatusDescription(for: status)
        }
    }

    func statusColor(for status: AgentCLIKit.AgentHarnessStatus?) -> Color {
        guard let status else {
            return .secondary
        }
        if !status.isEnabled {
            return .secondary
        }
        switch status.installation {
        case .unknown:
            return .blue
        case .missing:
            return .secondary
        case .installed:
            switch status.setup {
            case .ready:
                return .green
            case .needsSetup, .needsTrust, .unknown:
                return .orange
            case .failed:
                return .red
            }
        }
    }

    func effortOptions(for harnessId: String, model: String?) -> [AgentCLIKit.AgentHarnessOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: harnessId),
            selectedModel: model
        )
    }

    func harnessDisplayName(for harnessId: String) -> String {
        harnessStatus(for: harnessId)?.definition?.displayName
            ?? agentRegistry.agent(for: harnessId)?.name
            ?? harnessId.capitalized
    }

    func isHarnessEnabled(_ harnessId: String) -> Bool {
        settingsService.current.isHarnessEnabled(harnessId)
    }

    func setHarness(_ harnessId: String, enabled: Bool) {
        settingsService.update {
            $0.setHarness(harnessId, enabled: enabled)
        }
        Task {
            await refreshHarnessStatuses()
        }
    }

    func modelOptionValues(for harnessId: String, including selectedModel: String? = nil) -> [String] {
        let options = modelOptions(for: harnessId)
        var values = options.map(AgentModelOptionSelection.pickerValue(for:))
        if values.isEmpty {
            values = [AppSettings.defaultModelValue]
        }
        if let selectedModel,
           !selectedModel.isEmpty,
           AgentModelOptionSelection.option(in: options, matching: selectedModel) == nil,
           !values.contains(selectedModel) {
            values.append(AppSettings.normalizedModelSelection(selectedModel))
        }
        return values
    }

    func modelLabel(for model: String, harnessId: String) -> String {
        if let option = AgentModelOptionSelection.option(in: modelOptions(for: harnessId), matching: model) {
            return option.label
        }
        return ChatComposerTextSupport.modelLabel(for: model)
    }

    func modelOptions(for harnessId: String) -> [AgentCLIKit.AgentModelOption] {
        if let options = harnessStatus(for: harnessId)?.modelOptions, !options.isEmpty {
            return options
        }
        return ThreadDefaultResolver.modelOptions(for: harnessId, harnessStatuses: harnessStatuses)
    }

    func harnessVersion(for status: AgentCLIKit.AgentHarnessStatus?) -> String? {
        guard let version = status?.availability?.versionDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !version.isEmpty else {
            return nil
        }
        return version
    }

    func harnessExecutablePath(for status: AgentCLIKit.AgentHarnessStatus?) -> String? {
        status?.availability?.executablePath
    }

    /// The agent card renders version, path, and diagnostics as discrete fields, so the
    /// status description is redundant when it would repeat them: `statusDescription`
    /// prefers `diagnostics.first`, and an installed-and-ready harness's description is
    /// just "version at path" again.
    func showsStatusDescription(for status: AgentCLIKit.AgentHarnessStatus?) -> Bool {
        guard let status, status.isEnabled else {
            return true
        }
        if !status.diagnostics.isEmpty {
            return false
        }
        return !(status.installation == .installed && status.setup == .ready)
    }
}

private extension SettingsViewModel {
    var threadDefaultResolution: ThreadDefaultResolution {
        ThreadDefaultResolver.resolve(
            settings: settingsService.current,
            harnessOrdering: harnessOrdering,
            harnessStatuses: harnessStatuses,
            allowStaticFallback: harnessDiscovery == nil
        )
    }

    func persistResolvedThreadDefaultsIfNeeded() {
        let current = settingsService.current
        // A team launch treats inherited defaults as strict lead pins; persisting the Threads
        // runtime fallback here would silently replace an invalid lead while Settings opens.
        guard current.pullRequestReviewMode != .reviewTeam else {
            return
        }

        let resolution = threadDefaultResolution
        guard let harnessID = resolution.harnessID else {
            return
        }

        let nextDefaultModel = resolution.storedThreadModel ?? AppSettings.defaultModelValue
        guard current.defaultHarness != harnessID
            || current.defaultModel != nextDefaultModel
            || current.permissionMode != resolution.permissionMode
            || current.effort != resolution.effort else {
            return
        }

        settingsService.update {
            $0.defaultHarness = harnessID
            $0.defaultModel = nextDefaultModel
            $0.permissionMode = resolution.permissionMode
            $0.effort = resolution.effort
        }
    }

    func setupStatusLabel(for setup: AgentCLIKit.AgentHarnessReadinessState) -> String {
        switch setup {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs Setup"
        case .failed:
            return "Error"
        case .needsTrust:
            return "Needs Trust"
        case .unknown:
            return "Checking"
        }
    }

    func installedStatusDescription(for status: AgentCLIKit.AgentHarnessStatus) -> String {
        if status.setup == .needsSetup {
            return "CLI found, but it still needs authentication or setup."
        }
        if status.setup == .failed {
            return "Setup readiness check failed."
        }
        let version = harnessVersion(for: status)
        let path = harnessExecutablePath(for: status)
        if let version, let path {
            return "\(version) at \(path)"
        }
        if let path {
            return "Installed at \(path)"
        }
        return "Installed and ready."
    }
}
