import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsService: any SettingsService
    private let providerDetection: (any ProviderDetectionService)?
    private let agentRegistry: AgentRegistry

    var providerStatuses: [String: ProviderStatus] = [:]

    init(
        settingsService: any SettingsService,
        providerDetection: (any ProviderDetectionService)? = nil,
        agentRegistry: AgentRegistry = DefaultAgentRegistry()
    ) {
        self.settingsService = settingsService
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
    }

    var availableProviderIDs: [String] {
        AppSettings.supportedProviderIDs
    }

    func permissionModeOptions(for providerId: String) -> [String] {
        providerId == "claude" ? AppSettings.supportedPermissionModes : []
    }

    func installCommand(for providerId: String) -> String? {
        agentRegistry.agent(for: providerId)?.installCommand
    }

    func providerStatus(for providerId: String) -> ProviderStatus {
        providerStatuses[providerId] ?? .unchecked
    }

    func refreshProviderStatusesIfNeeded() async {
        guard providerStatuses.isEmpty else {
            return
        }
        await refreshProviderStatuses()
    }

    func refreshProviderStatuses() async {
        guard let providerDetection else {
            providerStatuses = [:]
            return
        }

        providerStatuses = Dictionary(uniqueKeysWithValues: availableProviderIDs.map { ($0, .unchecked) })
        await providerDetection.checkAllProviders()

        var newStatuses: [String: ProviderStatus] = [:]
        for providerId in availableProviderIDs {
            newStatuses[providerId] = await providerDetection.status(for: providerId)
        }
        providerStatuses = newStatuses
    }

    func shortStatusLabel(for status: ProviderStatus) -> String {
        switch status {
        case .connected:
            return "Connected"
        case .needsKey:
            return "Needs Key"
        case .missing:
            return "Missing"
        case .error:
            return "Error"
        case .unchecked:
            return "Checking"
        }
    }

    func statusDescription(for status: ProviderStatus) -> String {
        switch status {
        case .connected(let path, let version):
            return "\(version) at \(path)"
        case .needsKey:
            return "CLI found, but it still needs authentication or an API key."
        case .missing:
            return "Not installed on this Mac yet."
        case .error(let message):
            return message
        case .unchecked:
            return "Checking installation status."
        }
    }

    func statusColor(for status: ProviderStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .needsKey:
            return .orange
        case .missing:
            return .secondary
        case .error:
            return .red
        case .unchecked:
            return .blue
        }
    }

    func effortOptions(for providerId: String) -> [String] {
        providerId == "claude" ? AppSettings.supportedEffortLevels : []
    }

    var themeOptions: [String] {
        AppSettings.supportedThemes
    }

    var availableSoundNames: [String] {
        NotificationSettings.availableSoundNames
    }

    var defaultProvider: String {
        get { settingsService.current.defaultProvider }
        set { settingsService.update { $0.defaultProvider = newValue } }
    }

    var permissionMode: String {
        get { settingsService.current.permissionMode }
        set { settingsService.update { $0.permissionMode = newValue } }
    }

    var effort: String {
        get { settingsService.current.effort }
        set { settingsService.update { $0.effort = newValue } }
    }

    var autoGenerateNames: Bool {
        get { settingsService.current.autoGenerateNames }
        set { settingsService.update { $0.autoGenerateNames = newValue } }
    }

    var autoTrustWorktrees: Bool {
        get { settingsService.current.autoTrustWorktrees }
        set { settingsService.update { $0.autoTrustWorktrees = newValue } }
    }

    var createWorktreeByDefault: Bool {
        get { settingsService.current.createWorktreeByDefault }
        set { settingsService.update { $0.createWorktreeByDefault = newValue } }
    }

    var theme: String {
        get { settingsService.current.theme }
        set { settingsService.update { $0.theme = newValue } }
    }

    var codeFontFamily: String {
        get { settingsService.current.codeFontFamily }
        set { settingsService.update { $0.codeFontFamily = newValue } }
    }

    var codeFontSize: Int {
        get { settingsService.current.codeFontSize }
        set { settingsService.update { $0.codeFontSize = newValue } }
    }

    var chatFontSize: Int {
        get { settingsService.current.chatFontSize }
        set { settingsService.update { $0.chatFontSize = newValue } }
    }

    var notificationsEnabled: Bool {
        get { settingsService.current.notifications.enabled }
        set { settingsService.update { $0.notifications.enabled = newValue } }
    }

    var osNotificationsEnabled: Bool {
        get { settingsService.current.notifications.osNotifications }
        set { settingsService.update { $0.notifications.osNotifications = newValue } }
    }

    var soundEnabled: Bool {
        get { settingsService.current.notifications.sound }
        set { settingsService.update { $0.notifications.sound = newValue } }
    }

    var soundName: String {
        get {
            let storedSoundName = settingsService.current.notifications.soundName
            if let storedSoundName, availableSoundNames.contains(storedSoundName) {
                return storedSoundName
            }
            return NotificationSettings.defaultSoundName
        }
        set { settingsService.update { $0.notifications.soundName = newValue } }
    }

    var branchPrefix: String {
        get { settingsService.current.branchPrefix }
        set { settingsService.update { $0.branchPrefix = newValue } }
    }

    var pushOnCreate: Bool {
        get { settingsService.current.pushOnCreate }
        set { settingsService.update { $0.pushOnCreate = newValue } }
    }

    func providerConfig(for providerId: String) -> ProviderCustomConfig {
        settingsService.current.providerConfigs[providerId] ?? ProviderCustomConfig()
    }

    func updateProviderConfig(for providerId: String, _ transform: (inout ProviderCustomConfig) -> Void) {
        settingsService.update { settings in
            var config = settings.providerConfigs[providerId] ?? ProviderCustomConfig()
            transform(&config)
            settings.providerConfigs[providerId] = config
        }
    }
}
