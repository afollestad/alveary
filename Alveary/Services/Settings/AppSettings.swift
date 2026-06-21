import Foundation
import SwiftData

struct AppSettings: Codable, Sendable, Equatable {
    static let currentSettingsSchemaVersion = 1
    static let supportedProviderIDs = ["claude", "codex"]
    static let supportedPermissionModesByProvider = [
        "claude": ["default", "acceptEdits", "auto", "bypassPermissions"],
        "codex": ["untrusted", "on-request", "never"]
    ]
    static let supportedPermissionModes = ["default", "acceptEdits", "auto", "bypassPermissions", "untrusted", "on-request", "never"]
    static let defaultPermissionModeByProvider = [
        "claude": "default",
        "codex": "on-request"
    ]
    static let defaultEffortLevel = "medium"
    static let defaultModelValue = "default"
    static let supportedThemes = ["system", "light", "dark"]
    static let defaultCodeFontFamily = "SF Mono"
    static let supportedCodeFontSizeRange = 10...24
    static let supportedChatFontSizeRange = 11...24
    static let defaultEnterBehavior = ThreadEnterDefaultBehavior.queue
    static let supportedDiffViewerWidthRange = 320.0...960.0
    static let supportedDiffViewerSplitRange = 0.25...0.75
    static let defaultDiffViewerTopSectionFraction = 0.5
    static let defaultDiffViewerMode = DiffViewerMode.currentChanges
    static let supportedTerminalPaneHeightRange = 240.0...560.0
    static let defaultTerminalPaneHeight = 320.0
    static let supportedMaxTerminalSessionsRange = 1...50
    static let defaultMaxTerminalSessions = 10
    var settingsSchemaVersion = Self.currentSettingsSchemaVersion
    var lastSettingsPage = SettingsPage.agents
    var defaultProvider = "claude"
    var defaultModel = Self.defaultModelValue
    var permissionMode = "default"
    var effort = Self.defaultEffortLevel
    var disabledProviderIDs: Set<String> = []
    var defaultThreadCleanupAction = ThreadCleanupAction.archive
    var defaultEnterBehavior = Self.defaultEnterBehavior
    var reopenLastThreadAndConversationOnLaunch = true
    var turnAwake = TurnAwakeSettings()
    var autoTrustProjects = false
    var createWorktreeByDefault = false
    var theme = "system"
    var codeFontFamily = Self.defaultCodeFontFamily
    var codeFontSize = 12
    var chatFontSize = 13
    var diffViewerWidth = 380.0
    var diffViewerTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerCommitsTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerMode = Self.defaultDiffViewerMode
    var terminalPaneHeight = Self.defaultTerminalPaneHeight
    var expandTerminalWhenActionsRun = false
    var maxTerminalSessions = Self.defaultMaxTerminalSessions
    var contextManagementEnabled = false
    var sessionHandoffWindowPercentage = Self.defaultSessionHandoffWindowPercentage
    var handoffSteeringEnabled = true
    var handoffSteeringCountdownSeconds = Self.defaultHandoffSteeringCountdownSeconds
    var handoffPromptSendCountdownSeconds = Self.defaultHandoffPromptSendCountdownSeconds
    var handoffContextCustomizationEnabled = true
    var sessionHandoffPrompt = Self.defaultSessionHandoffPrompt
    var notifications = NotificationSettings()
    var branchPrefix = "alveary/"
    var commitMessageGenerationPrompt = Self.defaultCommitMessageGenerationPrompt
    var gitCommitIncludeUnstagedChanges = true
    var worktreesBaseDirectory = "~/Documents/worktrees"
    var lastAddProjectParentFolder: String?
    var providerConfigs: [String: ProviderCustomConfig] = [:]
    var lastOpenThreadID: PersistentIdentifier?
    var lastOpenConversationID: PersistentIdentifier?

    func normalized() -> AppSettings {
        var copy = self

        copy.normalizeProviderDefaults()
        copy.normalizeThreadDefaults()
        copy.turnAwake = copy.turnAwake.normalized()
        copy.normalizeAppearanceDefaults()
        copy.normalizeLayoutDefaults()
        copy.normalizeContextManagement()
        copy.normalizeNotificationDefaults()
        copy.normalizeProviderConfigs()
        copy.normalizeGitDefaults()
        copy.normalizeWorktreesBaseDirectory()
        return copy
    }

    var expandedWorktreesBaseDirectory: String {
        let trimmed = worktreesBaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? AppSettings().worktreesBaseDirectory : trimmed
        let expanded = (candidate as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        // Reject relative or otherwise malformed paths and fall back to the packaged default
        // so downstream `URL(fileURLWithPath:)` consumers always get an absolute root.
        return (AppSettings().worktreesBaseDirectory as NSString).expandingTildeInPath
    }

    static func normalizedEffortLevel(_ effort: String?) -> String {
        guard let effort = effort?.trimmingCharacters(in: .whitespacesAndNewlines),
              !effort.isEmpty else {
            return defaultEffortLevel
        }

        return effort
    }

    static func supportedPermissionModes(forProvider providerID: String) -> [String] {
        supportedPermissionModesByProvider[providerID] ?? []
    }

    static func defaultPermissionMode(forProvider providerID: String) -> String {
        defaultPermissionModeByProvider[providerID] ?? "default"
    }

    func isProviderEnabled(_ providerID: String) -> Bool {
        Self.supportedProviderIDs.contains(providerID) && !disabledProviderIDs.contains(providerID)
    }

    mutating func setProvider(_ providerID: String, enabled: Bool) {
        guard Self.supportedProviderIDs.contains(providerID) else {
            return
        }
        if enabled {
            disabledProviderIDs.remove(providerID)
        } else {
            disabledProviderIDs.insert(providerID)
        }
    }

    private mutating func normalizeProviderDefaults() {
        disabledProviderIDs = Set(disabledProviderIDs.filter(Self.supportedProviderIDs.contains))
        if disabledProviderIDs.count >= Self.supportedProviderIDs.count,
           let fallbackProvider = Self.supportedProviderIDs.first {
            disabledProviderIDs.remove(fallbackProvider)
        }

        if !Self.supportedProviderIDs.contains(defaultProvider) {
            defaultProvider = Self.supportedProviderIDs[0]
        }
        if !isProviderEnabled(defaultProvider),
           let fallbackProvider = Self.supportedProviderIDs.first(where: { isProviderEnabled($0) }) {
            defaultProvider = fallbackProvider
        }

        defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if defaultModel.isEmpty {
            defaultModel = Self.defaultModelValue
        }

        if !Self.supportedPermissionModes(forProvider: defaultProvider).contains(permissionMode) {
            permissionMode = Self.defaultPermissionMode(forProvider: defaultProvider)
        }
        effort = Self.normalizedEffortLevel(effort)
    }

    private mutating func normalizeThreadDefaults() {
        defaultEnterBehavior = Self.normalizedDefaultEnterBehavior(defaultEnterBehavior.rawValue)
    }

    private mutating func normalizeAppearanceDefaults() {
        if !Self.supportedThemes.contains(theme) {
            theme = "system"
        }
        codeFontFamily = codeFontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if codeFontFamily.isEmpty {
            codeFontFamily = Self.defaultCodeFontFamily
        }
        codeFontSize = min(
            max(codeFontSize, Self.supportedCodeFontSizeRange.lowerBound),
            Self.supportedCodeFontSizeRange.upperBound
        )
        chatFontSize = min(
            max(chatFontSize, Self.supportedChatFontSizeRange.lowerBound),
            Self.supportedChatFontSizeRange.upperBound
        )
    }

    private mutating func normalizeLayoutDefaults() {
        diffViewerWidth = min(
            max(diffViewerWidth, Self.supportedDiffViewerWidthRange.lowerBound),
            Self.supportedDiffViewerWidthRange.upperBound
        )
        diffViewerTopSectionFraction = min(
            max(diffViewerTopSectionFraction, Self.supportedDiffViewerSplitRange.lowerBound),
            Self.supportedDiffViewerSplitRange.upperBound
        )
        diffViewerCommitsTopSectionFraction = min(
            max(diffViewerCommitsTopSectionFraction, Self.supportedDiffViewerSplitRange.lowerBound),
            Self.supportedDiffViewerSplitRange.upperBound
        )
        diffViewerMode = Self.normalizedDiffViewerMode(diffViewerMode.rawValue)
        terminalPaneHeight = min(
            max(terminalPaneHeight, Self.supportedTerminalPaneHeightRange.lowerBound),
            Self.supportedTerminalPaneHeightRange.upperBound
        )
        maxTerminalSessions = min(
            max(maxTerminalSessions, Self.supportedMaxTerminalSessionsRange.lowerBound),
            Self.supportedMaxTerminalSessionsRange.upperBound
        )
    }

    private mutating func normalizeContextManagement() {
        sessionHandoffWindowPercentage = Self.normalizedSessionHandoffWindowPercentage(sessionHandoffWindowPercentage)
        handoffSteeringCountdownSeconds = Self.normalizedHandoffSteeringCountdownSeconds(handoffSteeringCountdownSeconds)
        handoffPromptSendCountdownSeconds = Self.normalizedHandoffPromptSendCountdownSeconds(handoffPromptSendCountdownSeconds)
        if sessionHandoffPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessionHandoffPrompt = Self.defaultSessionHandoffPrompt
        }
    }

    private mutating func normalizeNotificationDefaults() {
        if let soundName = notifications.soundName,
           !NotificationSettings.availableSoundNames.contains(soundName) {
            notifications.soundName = NotificationSettings.defaultSoundName
        }
    }

    private mutating func normalizeProviderConfigs() {
        providerConfigs = providerConfigs.reduce(into: [:]) { partialResult, entry in
            if let normalized = entry.value.normalized() {
                partialResult[entry.key] = normalized
            }
        }
    }

    private mutating func normalizeGitDefaults() {
        if commitMessageGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitMessageGenerationPrompt = Self.defaultCommitMessageGenerationPrompt
        }
    }

    private mutating func normalizeWorktreesBaseDirectory() {
        let trimmedWorktreesBase = worktreesBaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        worktreesBaseDirectory = trimmedWorktreesBase.isEmpty
            ? AppSettings().worktreesBaseDirectory
            : trimmedWorktreesBase
    }

    static func normalizedDiffViewerMode(_ rawValue: String?) -> DiffViewerMode {
        guard let rawValue,
              let mode = DiffViewerMode(rawValue: rawValue) else {
            return defaultDiffViewerMode
        }
        return mode
    }
}

extension AppSettings {
    enum SettingsPage: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
        case agents
        case interface
        case git
        case notifications
        case terminal
        case threads

        var id: String { rawValue }
    }

    enum CodingKeys: String, CodingKey {
        case lastSettingsPage
        case defaultProvider
        case defaultModel
        case permissionMode
        case effort
        case disabledProviderIDs
        case defaultThreadCleanupAction
        case defaultEnterBehavior
        case reopenLastThreadAndConversationOnLaunch
        case turnAwake
        case autoTrustProjects
        case createWorktreeByDefault
        case theme
        case codeFontFamily
        case codeFontSize
        case chatFontSize
        case diffViewerWidth
        case diffViewerTopSectionFraction
        case diffViewerCommitsTopSectionFraction
        case diffViewerMode
        case terminalPaneHeight
        case expandTerminalWhenActionsRun
        case maxTerminalSessions
        case contextManagementEnabled
        case sessionHandoffWindowPercentage
        case handoffSteeringEnabled
        case handoffSteeringCountdownSeconds
        case handoffPromptSendCountdownSeconds
        case handoffContextCustomizationEnabled
        case sessionHandoffPrompt
        case notifications
        case branchPrefix
        case commitMessageGenerationPrompt
        case gitCommitIncludeUnstagedChanges
        case worktreesBaseDirectory
        case lastAddProjectParentFolder
        case providerConfigs
        case lastOpenThreadID
        case lastOpenConversationID
        case settingsSchemaVersion
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case autoTrustWorktrees
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        let storedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion) ?? 0
        self = AppSettings()
        decodeLastSettingsPage(from: container)
        try decodeAgentDefaults(from: container, legacyContainer: legacyContainer)
        try decodeAppearance(from: container)
        try decodeLayout(from: container)
        try decodeContextManagement(from: container)
        try decodeStorage(from: container, storedSchemaVersion: storedSchemaVersion)
    }

    private mutating func decodeLastSettingsPage(from container: KeyedDecodingContainer<CodingKeys>) {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .lastSettingsPage),
              let page = SettingsPage(rawValue: rawValue) else {
            return
        }
        lastSettingsPage = page
    }

    private mutating func decodeAgentDefaults(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) throws {
        defaultProvider = try container.decodeIfPresent(String.self, forKey: .defaultProvider) ?? defaultProvider
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? defaultModel
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? permissionMode
        effort = try container.decodeIfPresent(String.self, forKey: .effort) ?? effort
        disabledProviderIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledProviderIDs) ?? disabledProviderIDs
        defaultThreadCleanupAction = try container.decodeIfPresent(
            ThreadCleanupAction.self,
            forKey: .defaultThreadCleanupAction
        ) ?? defaultThreadCleanupAction
        defaultEnterBehavior = Self.normalizedDefaultEnterBehavior(
            try container.decodeIfPresent(String.self, forKey: .defaultEnterBehavior)
        )
        reopenLastThreadAndConversationOnLaunch = try container.decodeIfPresent(
            Bool.self,
            forKey: .reopenLastThreadAndConversationOnLaunch
        ) ?? reopenLastThreadAndConversationOnLaunch
        turnAwake = try container.decodeIfPresent(TurnAwakeSettings.self, forKey: .turnAwake) ?? turnAwake
        autoTrustProjects = try container.decodeIfPresent(Bool.self, forKey: .autoTrustProjects)
            ?? legacyContainer.decodeIfPresent(Bool.self, forKey: .autoTrustWorktrees)
            ?? autoTrustProjects
        createWorktreeByDefault = try container.decodeIfPresent(
            Bool.self,
            forKey: .createWorktreeByDefault
        ) ?? createWorktreeByDefault
    }

    private mutating func decodeAppearance(from container: KeyedDecodingContainer<CodingKeys>) throws {
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? theme
        codeFontFamily = try container.decodeIfPresent(String.self, forKey: .codeFontFamily) ?? codeFontFamily
        codeFontSize = try container.decodeIfPresent(Int.self, forKey: .codeFontSize) ?? codeFontSize
        chatFontSize = try container.decodeIfPresent(Int.self, forKey: .chatFontSize) ?? chatFontSize
    }

    private mutating func decodeLayout(from container: KeyedDecodingContainer<CodingKeys>) throws {
        diffViewerWidth = try container.decodeIfPresent(Double.self, forKey: .diffViewerWidth) ?? diffViewerWidth
        diffViewerTopSectionFraction = try container.decodeIfPresent(
            Double.self,
            forKey: .diffViewerTopSectionFraction
        ) ?? diffViewerTopSectionFraction
        diffViewerCommitsTopSectionFraction = try container.decodeIfPresent(
            Double.self,
            forKey: .diffViewerCommitsTopSectionFraction
        ) ?? diffViewerCommitsTopSectionFraction
        diffViewerMode = Self.normalizedDiffViewerMode(
            try container.decodeIfPresent(String.self, forKey: .diffViewerMode)
        )
        terminalPaneHeight = try container.decodeIfPresent(Double.self, forKey: .terminalPaneHeight) ?? terminalPaneHeight
        expandTerminalWhenActionsRun = try container.decodeIfPresent(
            Bool.self,
            forKey: .expandTerminalWhenActionsRun
        ) ?? expandTerminalWhenActionsRun
        maxTerminalSessions = try container.decodeIfPresent(Int.self, forKey: .maxTerminalSessions) ?? maxTerminalSessions
    }

    private mutating func decodeContextManagement(from container: KeyedDecodingContainer<CodingKeys>) throws {
        contextManagementEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .contextManagementEnabled
        ) ?? contextManagementEnabled
        sessionHandoffWindowPercentage = try container.decodeIfPresent(
            Int.self,
            forKey: .sessionHandoffWindowPercentage
        ) ?? sessionHandoffWindowPercentage
        handoffSteeringEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .handoffSteeringEnabled
        ) ?? handoffSteeringEnabled
        handoffSteeringCountdownSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .handoffSteeringCountdownSeconds
        ) ?? handoffSteeringCountdownSeconds
        handoffPromptSendCountdownSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .handoffPromptSendCountdownSeconds
        ) ?? handoffPromptSendCountdownSeconds
        handoffContextCustomizationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .handoffContextCustomizationEnabled
        ) ?? handoffContextCustomizationEnabled
        sessionHandoffPrompt = try container.decodeIfPresent(String.self, forKey: .sessionHandoffPrompt) ?? sessionHandoffPrompt
    }

    private mutating func decodeStorage(
        from container: KeyedDecodingContainer<CodingKeys>,
        storedSchemaVersion: Int
    ) throws {
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? notifications
        let decodedBranchPrefix = try container.decodeIfPresent(String.self, forKey: .branchPrefix)
        branchPrefix = Self.migratedBranchPrefix(
            decodedBranchPrefix ?? branchPrefix,
            storedSchemaVersion: storedSchemaVersion
        )
        commitMessageGenerationPrompt = try container.decodeIfPresent(
            String.self,
            forKey: .commitMessageGenerationPrompt
        ) ?? commitMessageGenerationPrompt
        gitCommitIncludeUnstagedChanges = try container.decodeIfPresent(
            Bool.self,
            forKey: .gitCommitIncludeUnstagedChanges
        ) ?? gitCommitIncludeUnstagedChanges
        worktreesBaseDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .worktreesBaseDirectory
        ) ?? worktreesBaseDirectory
        lastAddProjectParentFolder = try container.decodeIfPresent(String.self, forKey: .lastAddProjectParentFolder)
        providerConfigs = try container.decodeIfPresent([String: ProviderCustomConfig].self, forKey: .providerConfigs)
            ?? providerConfigs
        lastOpenThreadID = try? container.decodeIfPresent(PersistentIdentifier.self, forKey: .lastOpenThreadID)
        lastOpenConversationID = try? container.decodeIfPresent(PersistentIdentifier.self, forKey: .lastOpenConversationID)
    }

    private static func migratedBranchPrefix(_ branchPrefix: String, storedSchemaVersion: Int) -> String {
        if storedSchemaVersion == 0,
           !branchPrefix.isEmpty,
           !branchPrefix.hasSuffix("/") {
            return branchPrefix + "/"
        }
        return branchPrefix
    }

    private static func normalizedDefaultEnterBehavior(_ rawValue: String?) -> ThreadEnterDefaultBehavior {
        guard let rawValue,
              let behavior = ThreadEnterDefaultBehavior(rawValue: rawValue) else {
            return defaultEnterBehavior
        }
        return behavior
    }
}
