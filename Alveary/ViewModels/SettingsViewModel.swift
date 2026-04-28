import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsService: any SettingsService
    private let providerDetection: (any ProviderDetectionService)?
    private let agentRegistry: AgentRegistry
    @ObservationIgnored private let codeFontFamilyLoader: @MainActor () -> [String]
    @ObservationIgnored private let soundPreviewer: @MainActor (String) -> Void

    var providerStatuses: [String: ProviderStatus] = [:]
    private var loadedCodeFontFamilyOptions: [String]?

    init(
        settingsService: any SettingsService,
        providerDetection: (any ProviderDetectionService)? = nil,
        agentRegistry: AgentRegistry = DefaultAgentRegistry(),
        codeFontFamilyLoader: @escaping @MainActor () -> [String] = { NSFontManager.shared.availableFontFamilies },
        soundPreviewer: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.settingsService = settingsService
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.codeFontFamilyLoader = codeFontFamilyLoader
        self.soundPreviewer = soundPreviewer
    }

    var availableProviderIDs: [String] {
        AppSettings.supportedProviderIDs
    }

    var supportedModels: [String] {
        AppSettings.supportedModels
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

    func effortOptions(for providerId: String, model: String?) -> [String] {
        providerId == "claude" ? AppSettings.supportedEffortLevels(forModel: model) : []
    }

    var themeOptions: [String] {
        AppSettings.supportedThemes
    }

    var availableSoundNames: [String] {
        NotificationSettings.availableSoundNames
    }

    var codeFontFamilyOptions: [String] {
        loadedCodeFontFamilyOptions ?? [AppSettings.defaultCodeFontFamily]
    }

    func loadCodeFontFamilyOptionsIfNeeded() {
        guard loadedCodeFontFamilyOptions == nil else {
            return
        }
        loadedCodeFontFamilyOptions = Self.normalizedCodeFontFamilies(codeFontFamilyLoader())
    }

    var defaultProvider: String {
        get { settingsService.current.defaultProvider }
        set { settingsService.update { $0.defaultProvider = newValue } }
    }

    var defaultModel: String {
        get { settingsService.current.defaultModel }
        set {
            settingsService.update { settings in
                let previousEffort = settings.effort
                settings.defaultModel = newValue
                // Mirror the per-thread coercion in `ConversationViewModel.applyModelChange`
                // so the Settings Effort picker can never leave a value selected that the
                // new model doesn't support, and so the "didn't customize effort" case
                // lands on the new model's preferred default (e.g. Opus → `xhigh`).
                let needsFallback = !AppSettings.effortLevel(previousEffort, isSupportedByModel: newValue)
                    || previousEffort == AppSettings.defaultEffortLevel
                if needsFallback {
                    settings.effort = AppSettings.defaultEffortLevel(forModel: newValue)
                }
            }
        }
    }

    var permissionMode: String {
        get { settingsService.current.permissionMode }
        set { settingsService.update { $0.permissionMode = newValue } }
    }

    var effort: String {
        get { settingsService.current.effort }
        set { settingsService.update { $0.effort = newValue } }
    }

    var deleteKeyAction: ThreadDeleteKeyAction {
        get { settingsService.current.deleteKeyAction }
        set { settingsService.update { $0.deleteKeyAction = newValue } }
    }

    var defaultEnterBehavior: ThreadEnterDefaultBehavior {
        get { settingsService.current.defaultEnterBehavior }
        set { settingsService.update { $0.defaultEnterBehavior = newValue } }
    }

    var reopenLastThreadAndConversationOnLaunch: Bool {
        get { settingsService.current.reopenLastThreadAndConversationOnLaunch }
        set { settingsService.update { $0.reopenLastThreadAndConversationOnLaunch = newValue } }
    }

    var autoTrustProjects: Bool {
        get { settingsService.current.autoTrustProjects }
        set { settingsService.update { $0.autoTrustProjects = newValue } }
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
        get {
            let storedFontFamily = settingsService.current.codeFontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
            return storedFontFamily.isEmpty ? AppSettings.defaultCodeFontFamily : storedFontFamily
        }
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

    var expandTerminalWhenActionsRun: Bool {
        get { settingsService.current.expandTerminalWhenActionsRun }
        set { settingsService.update { $0.expandTerminalWhenActionsRun = newValue } }
    }

    var maxTerminalSessions: Int {
        get { settingsService.current.maxTerminalSessions }
        set { settingsService.update { $0.maxTerminalSessions = newValue } }
    }

    var contextManagementEnabled: Bool {
        get { settingsService.current.contextManagementEnabled }
        set { settingsService.update { $0.contextManagementEnabled = newValue } }
    }

    var sessionHandoffWindowPercentage: Int {
        get { settingsService.current.sessionHandoffWindowPercentage }
        set { settingsService.update { $0.sessionHandoffWindowPercentage = newValue } }
    }

    var handoffContextCustomizationEnabled: Bool {
        get { settingsService.current.handoffContextCustomizationEnabled }
        set { settingsService.update { $0.handoffContextCustomizationEnabled = newValue } }
    }

    var sessionHandoffPrompt: String {
        get { settingsService.current.sessionHandoffPrompt }
        set { settingsService.update { $0.sessionHandoffPrompt = newValue } }
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
        set {
            settingsService.update { $0.notifications.soundName = newValue }

            let notifications = settingsService.current.notifications
            guard notifications.enabled,
                  notifications.sound,
                  availableSoundNames.contains(newValue) else {
                return
            }

            soundPreviewer(newValue)
        }
    }

    var branchPrefix: String {
        get { settingsService.current.branchPrefix }
        set { settingsService.update { $0.branchPrefix = newValue } }
    }

    var worktreesBaseDirectory: String {
        get { settingsService.current.worktreesBaseDirectory }
        set { settingsService.update { $0.worktreesBaseDirectory = newValue } }
    }

    func providerExtraArgs(for providerId: String) -> String? {
        settingsService.current.providerConfigs[providerId]?.extraArgs
    }

    func updateProviderExtraArgs(for providerId: String, extraArgs: String?) {
        settingsService.update { settings in
            var config = settings.providerConfigs[providerId] ?? ProviderCustomConfig()
            config.extraArgs = extraArgs
            settings.providerConfigs[providerId] = config
        }
    }

    static func normalizedCodeFontFamilies(_ fontFamilies: [String]) -> [String] {
        sortedUniqueCodeFontFamilies(fontFamilies + [AppSettings.defaultCodeFontFamily])
    }

    private static func sortedUniqueCodeFontFamilies(_ fontFamilies: [String]) -> [String] {
        var seen = Set<String>()
        let uniqueFamilies = fontFamilies.compactMap { family -> String? in
            let trimmedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFamily.isEmpty,
                  seen.insert(trimmedFamily).inserted else {
                return nil
            }
            return trimmedFamily
        }
        let sortedFamilies = uniqueFamilies.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return sortedFamilies
    }
}
