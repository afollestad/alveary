import AgentCLIKit
import SwiftUI

extension SettingsViewModel {
    var availableProviderIDs: [String] {
        let ordered = providerOrdering.isEmpty ? AppSettings.supportedProviderIDs : providerOrdering
        let supported = ordered.filter(AppSettings.supportedProviderIDs.contains)
        return supported.isEmpty ? AppSettings.supportedProviderIDs : supported
    }

    var supportedModels: [String] {
        modelOptionValues(for: defaultProvider, including: settingsService.current.defaultModel)
    }

    var defaultProvider: String {
        get { settingsService.current.defaultProvider }
        set {
            let options = modelOptions(for: newValue)
            settingsService.update { settings in
                settings.defaultProvider = newValue
                settings.setProvider(newValue, enabled: true)
                if AgentModelOptionSelection.option(in: options, matching: settings.defaultModel) == nil {
                    settings.defaultModel = AppSettings.defaultModelValue
                }
                if !AppSettings.supportedPermissionModes(forProvider: newValue).contains(settings.permissionMode) {
                    settings.permissionMode = AppSettings.defaultPermissionMode(forProvider: newValue)
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
                in: modelOptions(for: settingsService.current.defaultProvider),
                matching: settingsService.current.defaultModel
            )
        }
        set {
            let options = modelOptions(for: settingsService.current.defaultProvider)
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
                let supportedModes = AppSettings.supportedPermissionModes(forProvider: settings.defaultProvider)
                settings.permissionMode = supportedModes.contains(newValue)
                    ? newValue
                    : AppSettings.defaultPermissionMode(forProvider: settings.defaultProvider)
            }
        }
    }

    func permissionModeOptions(for providerId: String) -> [String] {
        if let status = providerStatus(for: providerId),
           let modes = status.definition?.supportedPermissionModes {
            return modes.map(\.value).filter { $0 != "plan" }
        }
        return AppSettings.supportedPermissionModes(forProvider: providerId)
    }

    func installCommand(for providerId: String) -> String? {
        agentRegistry.agent(for: providerId)?.installCommand
    }

    func providerStatus(for providerId: String) -> AgentCLIKit.AgentProviderStatus? {
        if let status = providerStatuses[providerId] {
            return status
        }
        guard let id = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return nil
        }
        return AgentCLIKit.AgentProviderStatus(
            providerId: id,
            definition: nil,
            installation: .unknown,
            isEnabled: settingsService.current.isProviderEnabled(providerId),
            setup: .unknown,
            modelOptions: defaultModelOptions(for: id)
        )
    }

    func refreshProviderStatusesIfNeeded() async {
        guard providerStatuses.isEmpty else {
            return
        }
        await refreshProviderStatuses()
    }

    func refreshProviderStatuses() async {
        guard let providerDiscovery else {
            providerStatuses = [:]
            providerOrdering = AppSettings.supportedProviderIDs
            return
        }

        let ordering = await providerDiscovery.stableProviderOrdering().map(\.rawValue)
        let statuses = await providerDiscovery.providerStatuses(projectURL: nil)

        providerOrdering = ordering
        providerStatuses = Dictionary(
            uniqueKeysWithValues: statuses.map { ($0.key.rawValue, $0.value) }
        )
    }

    func shortStatusLabel(for status: AgentCLIKit.AgentProviderStatus?) -> String {
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

    func statusDescription(for status: AgentCLIKit.AgentProviderStatus?) -> String {
        guard let status else {
            return "Provider is not registered."
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

    func statusColor(for status: AgentCLIKit.AgentProviderStatus?) -> Color {
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

    func effortOptions(for providerId: String, model: String?) -> [AgentCLIKit.AgentProviderOption] {
        AgentModelOptionSelection.effortOptions(
            in: modelOptions(for: providerId),
            selectedModel: model
        )
    }

    func providerDisplayName(for providerId: String) -> String {
        providerStatus(for: providerId)?.definition?.displayName
            ?? agentRegistry.agent(for: providerId)?.name
            ?? providerId.capitalized
    }

    func isProviderEnabled(_ providerId: String) -> Bool {
        settingsService.current.isProviderEnabled(providerId)
    }

    func setProvider(_ providerId: String, enabled: Bool) {
        settingsService.update {
            $0.setProvider(providerId, enabled: enabled)
        }
        Task {
            await refreshProviderStatuses()
        }
    }

    func modelOptionValues(for providerId: String, including selectedModel: String? = nil) -> [String] {
        let options = modelOptions(for: providerId)
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

    func modelLabel(for model: String, providerId: String) -> String {
        if let option = AgentModelOptionSelection.option(in: modelOptions(for: providerId), matching: model) {
            return option.label
        }
        return ChatComposerTextSupport.modelLabel(for: model)
    }

    func modelOptions(for providerId: String) -> [AgentCLIKit.AgentModelOption] {
        if let options = providerStatus(for: providerId)?.modelOptions, !options.isEmpty {
            return options
        }
        guard let id = AgentCLIKit.AgentProviderID(rawValue: providerId) else {
            return []
        }
        return defaultModelOptions(for: id)
    }
}

private extension SettingsViewModel {
    func setupStatusLabel(for setup: AgentCLIKit.AgentProviderReadinessState) -> String {
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

    func installedStatusDescription(for status: AgentCLIKit.AgentProviderStatus) -> String {
        if status.setup == .needsSetup {
            return "CLI found, but it still needs authentication or setup."
        }
        if status.setup == .failed {
            return "Setup readiness check failed."
        }
        let version = status.availability?.versionDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = status.availability?.executablePath
        if let version, !version.isEmpty, let path {
            return "\(version) at \(path)"
        }
        if let path {
            return "Installed at \(path)"
        }
        return "Installed and ready."
    }

    func defaultModelOptions(for providerId: AgentCLIKit.AgentProviderID) -> [AgentCLIKit.AgentModelOption] {
        AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: providerId)
    }
}
