import AgentCLIKit
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored let settingsService: any SettingsService
    @ObservationIgnored let providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)?
    @ObservationIgnored let agentRegistry: AgentRegistry
    @ObservationIgnored private let codeFontFamilyLoader: @MainActor () -> [String]
    @ObservationIgnored private let soundPreviewer: @MainActor (String) -> Void

    var providerStatuses: [String: AgentCLIKit.AgentProviderStatus] = [:]
    var providerOrdering: [String] = []
    private var loadedCodeFontFamilyOptions: [String]?

    init(
        settingsService: any SettingsService,
        providerDiscovery: (any AgentCLIKit.AgentProviderDiscoveryService)? = nil,
        agentRegistry: AgentRegistry = DefaultAgentRegistry(),
        codeFontFamilyLoader: @escaping @MainActor () -> [String] = { NSFontManager.shared.availableFontFamilies },
        soundPreviewer: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.settingsService = settingsService
        self.providerDiscovery = providerDiscovery
        self.agentRegistry = agentRegistry
        self.codeFontFamilyLoader = codeFontFamilyLoader
        self.soundPreviewer = soundPreviewer
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

    var effort: String {
        get { settingsService.current.effort }
        set {
            let options = modelOptions(for: settingsService.current.defaultProvider)
            settingsService.update {
                $0.effort = AgentModelOptionSelection.normalizedEffort(
                    newValue,
                    options: options,
                    selectedModel: $0.defaultModel
                )
            }
        }
    }

    var defaultThreadCleanupAction: ThreadCleanupAction {
        get { settingsService.current.defaultThreadCleanupAction }
        set { settingsService.update { $0.defaultThreadCleanupAction = newValue } }
    }

    var defaultEnterBehavior: ThreadEnterDefaultBehavior {
        get { settingsService.current.defaultEnterBehavior }
        set { settingsService.update { $0.defaultEnterBehavior = newValue } }
    }

    var reopenLastThreadAndConversationOnLaunch: Bool {
        get { settingsService.current.reopenLastThreadAndConversationOnLaunch }
        set { settingsService.update { $0.reopenLastThreadAndConversationOnLaunch = newValue } }
    }

    var turnAwakeEnabled: Bool {
        get { settingsService.current.turnAwake.enabled }
        set { settingsService.update { $0.turnAwake.enabled = newValue } }
    }

    var turnAwakePreventDisplaySleep: Bool {
        get { settingsService.current.turnAwake.preventDisplaySleep }
        set { settingsService.update { $0.turnAwake.preventDisplaySleep = newValue } }
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

    var sessionHandoffCommandEnabled: Bool {
        get { settingsService.current.sessionHandoffCommandEnabled }
        set { settingsService.update { $0.sessionHandoffCommandEnabled = newValue } }
    }

    var sessionHandoffWindowPercentage: Int {
        get { settingsService.current.sessionHandoffWindowPercentage }
        set { settingsService.update { $0.sessionHandoffWindowPercentage = newValue } }
    }

    var handoffSteeringEnabled: Bool {
        get { settingsService.current.handoffSteeringEnabled }
        set { settingsService.update { $0.handoffSteeringEnabled = newValue } }
    }

    var handoffSteeringCountdownSeconds: Int {
        get { settingsService.current.handoffSteeringCountdownSeconds }
        set { settingsService.update { $0.handoffSteeringCountdownSeconds = newValue } }
    }

    var handoffPromptSendCountdownSeconds: Int {
        get { settingsService.current.handoffPromptSendCountdownSeconds }
        set { settingsService.update { $0.handoffPromptSendCountdownSeconds = newValue } }
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
