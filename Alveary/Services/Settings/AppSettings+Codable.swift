import Foundation
import SwiftData

// Settings pages, coding keys, and tolerant decoding for `AppSettings`.
extension AppSettings {
    enum SettingsPage: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
        case agents
        case interface
        case appShots
        case git
        case handoff
        case notifications
        case terminal
        case threads
        case appUpdates

        var id: String { rawValue }
    }

    enum CodingKeys: String, CodingKey {
        case lastSettingsPage
        case hasCompletedOnboarding
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
        case skillsPaneWidth
        case mcpPaneWidth
        case scheduledTasksPaneWidth
        case pullRequestsPaneWidth
        case diffViewerTopSectionFraction
        case diffViewerCommitsTopSectionFraction
        case diffViewerMode
        case terminalPaneHeight
        case expandTerminalWhenActionsRun
        case maxTerminalSessions
        case appShotsEnabled
        case appShotShortcut
        case voiceInputShortcut
        case voiceInputShortcutMigrationCompleted
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
        case lastActiveProjectPath
        case lastOpenThreadID
        case lastOpenConversationID
        case settingsSchemaVersion
        case pullRequestsSelectedTab
        case pullRequestsStatusFilters
        case pullRequestsRepositoryFilters
        case scheduledTasksSelectedTab
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case autoTrustWorktrees
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        let storedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion) ?? 0
        self = AppSettings()
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? hasCompletedOnboarding
        decodeLastSettingsPage(from: container)
        try decodeAgentDefaults(from: container, legacyContainer: legacyContainer)
        try decodeAppearance(from: container)
        try decodeLayout(from: container)
        try decodeContextManagement(from: container)
        try decodeStorage(from: container, storedSchemaVersion: storedSchemaVersion)
        decodeScreenTabs(from: container)
    }

    private mutating func decodeScreenTabs(from container: KeyedDecodingContainer<CodingKeys>) {
        if let tab = try? container.decodeIfPresent(String.self, forKey: .pullRequestsSelectedTab) {
            pullRequestsSelectedTab = tab
        }
        if let tab = try? container.decodeIfPresent(String.self, forKey: .scheduledTasksSelectedTab) {
            scheduledTasksSelectedTab = tab
        }
        // Element-tolerant: unknown status strings drop out instead of failing the load.
        if let rawStatuses = try? container.decodeIfPresent([String].self, forKey: .pullRequestsStatusFilters) {
            pullRequestsStatusFilters = Set(rawStatuses.compactMap(PullRequestStatus.init(rawValue:)))
        }
        if let repositories = try? container.decodeIfPresent(Set<String>.self, forKey: .pullRequestsRepositoryFilters) {
            pullRequestsRepositoryFilters = repositories
        }
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
        skillsPaneWidth = try container.decodeIfPresent(Double.self, forKey: .skillsPaneWidth) ?? skillsPaneWidth
        mcpPaneWidth = try container.decodeIfPresent(Double.self, forKey: .mcpPaneWidth) ?? mcpPaneWidth
        scheduledTasksPaneWidth = try container.decodeIfPresent(
            Double.self,
            forKey: .scheduledTasksPaneWidth
        ) ?? scheduledTasksPaneWidth
        pullRequestsPaneWidth = try container.decodeIfPresent(
            Double.self,
            forKey: .pullRequestsPaneWidth
        ) ?? pullRequestsPaneWidth
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
        appShotsEnabled = try container.decodeIfPresent(Bool.self, forKey: .appShotsEnabled) ?? appShotsEnabled
        appShotShortcut = Self.normalizedAppShotShortcut(from: container)
        decodeVoiceInputShortcut(from: container)
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
        lastActiveProjectPath = try container.decodeIfPresent(String.self, forKey: .lastActiveProjectPath)
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

    static func normalizedDefaultEnterBehavior(_ rawValue: String?) -> ThreadEnterDefaultBehavior {
        guard let rawValue,
              let behavior = ThreadEnterDefaultBehavior(rawValue: rawValue) else {
            return defaultEnterBehavior
        }
        return behavior
    }
}
