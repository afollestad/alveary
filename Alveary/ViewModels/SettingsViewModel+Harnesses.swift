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

    var threadDefaultHarnessSelection: String {
        threadDefaultResolution.harnessID ?? settingsService.current.defaultHarness
    }

    var threadDefaultPermissionModeOptions: [String] {
        guard let harnessID = threadDefaultResolution.harnessID else {
            return []
        }
        return permissionModeOptions(for: harnessID)
    }

    /// Lists only ready harnesses; a stored default that is not ready still reads on the button, with effort hidden.
    var threadDefaultAgentPresentation: AgentReasoningPresentation {
        let settings = settingsService.current
        return AgentReasoningPresentation(
            harnesses: threadDefaultHarnessIDs.map { agentReasoningHarness(for: $0) },
            pins: .init(harnessID: settings.defaultHarness, model: settings.defaultModel, effort: settings.effort),
            effective: threadDefaultResolvedAgent,
            isChecking: isCheckingThreadDefaultHarnesses
        )
    }

    /// What new threads launch with, which hosts inheriting the Threads default also resolve to.
    var threadDefaultResolvedAgent: AgentReasoningPresentation.Resolved {
        let resolution = threadDefaultResolution
        return AgentReasoningPresentation.Resolved(
            harness: agentReasoningHarness(for: resolution.harnessID ?? settingsService.current.defaultHarness),
            model: resolution.storedThreadModel ?? AppSettings.defaultModelValue,
            effort: resolution.effort
        )
    }

    var threadDefaultResolution: ThreadDefaultResolution {
        ThreadDefaultResolver.resolve(
            settings: settingsService.current,
            harnessOrdering: harnessOrdering,
            harnessStatuses: harnessStatuses,
            allowStaticFallback: harnessDiscovery == nil
        )
    }

    /// Writes a pick in one update so harness, model, effort, and permission invalidate together. A model change seeds
    /// that model's default effort while the stored effort is still the untouched `AppSettings.defaultEffortLevel`,
    /// because new threads seed from it. The change is measured against the resolved agent, not the stored fields: an
    /// effort drag pins the resolved harness and model, which differ from the stored ones after a fallback.
    func applyThreadDefaultAgent(_ pins: AgentReasoningPins) -> Bool {
        guard let harnessID = pins.harnessID, let model = pins.model, let effort = pins.effort else {
            return false
        }
        let options = modelOptions(for: harnessID)
        let resolved = threadDefaultAgentPresentation.effective
        let changesModel = resolved.harness.id != harnessID || resolved.model != model
        settingsService.update { settings in
            let seedsModelDefault = settings.effort == AppSettings.defaultEffortLevel && changesModel
            settings.defaultHarness = harnessID
            settings.setHarness(harnessID, enabled: true)
            settings.defaultModel = model
            if !AppSettings.supportedPermissionModes(forHarness: harnessID).contains(settings.permissionMode) {
                settings.permissionMode = AppSettings.defaultPermissionMode(forHarness: harnessID)
            }
            settings.effort = seedsModelDefault
                ? AgentModelOptionSelection.defaultEffortValue(in: options, selectedModel: model)
                : AgentModelOptionSelection.normalizedEffort(effort, options: options, selectedModel: model)
        }
        return true
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

    /// `concreteModelOptions` replaces the harness's full catalog for a host that launches only concrete models.
    func agentReasoningHarness(
        for harnessID: String,
        concreteModelOptions: [AgentCLIKit.AgentModelOption]? = nil
    ) -> AgentReasoningPresentation.Harness {
        AgentReasoningPresentation.Harness(
            id: harnessID,
            title: harnessDisplayName(for: harnessID),
            modelOptions: concreteModelOptions ?? modelOptions(for: harnessID),
            requiresConcreteModel: concreteModelOptions != nil
        )
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
