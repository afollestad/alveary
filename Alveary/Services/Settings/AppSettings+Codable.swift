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
        case rightPaneWidth
        case pullRequestsEnabled
        case automaticallyLinkPullRequests
        case suppressPullRequestLinkPrompts
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
        case pullRequestGenerationPrompt
        case pullRequestReviewPrompt
        case pullRequestAddressFeedbackPrompt
        case pullRequestReviewProvider
        case pullRequestReviewModel
        case pullRequestReviewEffort
        case gitCommitIncludeUnstagedChanges
        case worktreesBaseDirectory
        case lastAddProjectParentFolder
        case providerConfigs
        case lastActiveProjectPath
        case lastOpenThreadID
        case lastOpenConversationID
        case settingsSchemaVersion
        case pullRequestsSelectedTab
        case pullRequestsStatusFilter
        case pullRequestsRepositoryFilters
        case scheduledTasksSelectedTab
        case pullRequestOwnFooterActionKind
        case pullRequestOthersFooterActionKind
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case autoTrustWorktrees
        // The multi-select status filter, before it became single-select so it could be pushed
        // into the GitHub search (whose qualifiers only AND).
        case pullRequestsStatusFilters
        // One footer pick for every pull request, before the split into an authored and an
        // others default.
        case pullRequestReviewFooterActionKind
        // The lane used to persist a width per destination — `diffViewerWidth`,
        // `skillsPaneWidth`, `mcpPaneWidth`, `scheduledTasksPaneWidth`, and
        // `pullRequestsPaneWidth`. Only the Diff Viewer's is read back, because
        // it is the pane users sized most often; the rest are dropped on the
        // next encode.
        case diffViewerWidth
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
        try decodeLayout(from: container, legacyContainer: legacyContainer)
        try decodeContextManagement(from: container)
        try decodeStorage(from: container, storedSchemaVersion: storedSchemaVersion)
        decodeScreenTabs(from: container, legacyContainer: legacyContainer)
    }

    private mutating func decodeScreenTabs(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) {
        if let tab = try? container.decodeIfPresent(String.self, forKey: .pullRequestsSelectedTab) {
            pullRequestsSelectedTab = tab
        }
        if let tab = try? container.decodeIfPresent(String.self, forKey: .scheduledTasksSelectedTab) {
            scheduledTasksSelectedTab = tab
        }
        decodePullRequestsStatusFilter(from: container, legacyContainer: legacyContainer)
        if let repositories = try? container.decodeIfPresent(Set<String>.self, forKey: .pullRequestsRepositoryFilters) {
            pullRequestsRepositoryFilters = repositories
        }
        decodeFooterActionKinds(from: container, legacyContainer: legacyContainer)
    }

    /// The multi-select predecessor carries over only when it named exactly one status, which is
    /// all single-select can express; no selection (its old default) or a combination takes the
    /// new packaged default instead, so an upgrade lands on open-only rather than on "everything".
    private mutating func decodePullRequestsStatusFilter(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) {
        if let filter = try? container.decodeIfPresent(PullRequestStatusFilter.self, forKey: .pullRequestsStatusFilter) {
            pullRequestsStatusFilter = filter
            return
        }
        // Element-tolerant like the decode it replaces: an unknown status string drops out.
        guard let rawStatuses = try? legacyContainer.decodeIfPresent(
            [String].self,
            forKey: .pullRequestsStatusFilters
        ) else {
            return
        }
        let statuses = rawStatuses.compactMap(PullRequestStatus.init(rawValue:))
        guard statuses.count == 1, let status = statuses.first else {
            return
        }
        pullRequestsStatusFilter = PullRequestStatusFilter(status)
    }

    /// The one footer pick that preceded the split seeds *both* new keys, but only when it names
    /// something other than its own old default: every settings file ever encoded carries
    /// `"submitReview"` whether the user chose it or never touched the caret, so honouring that
    /// value would hand the whole install base a stored pick nobody made and hide the
    /// authorship-aware defaults from everyone.
    private mutating func decodeFooterActionKinds(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) {
        if let legacy = try? legacyContainer.decodeIfPresent(String.self, forKey: .pullRequestReviewFooterActionKind),
           legacy != "submitReview" {
            pullRequestOwnFooterActionKind = legacy
            pullRequestOthersFooterActionKind = legacy
        }
        if let kind = try? container.decodeIfPresent(String.self, forKey: .pullRequestOwnFooterActionKind) {
            pullRequestOwnFooterActionKind = kind
        }
        if let kind = try? container.decodeIfPresent(String.self, forKey: .pullRequestOthersFooterActionKind) {
            pullRequestOthersFooterActionKind = kind
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

    private mutating func decodeLayout(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) throws {
        rightPaneWidth = try container.decodeIfPresent(Double.self, forKey: .rightPaneWidth)
            ?? legacyContainer.decodeIfPresent(Double.self, forKey: .diffViewerWidth)
            ?? rightPaneWidth
        pullRequestsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .pullRequestsEnabled
        ) ?? pullRequestsEnabled
        automaticallyLinkPullRequests = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyLinkPullRequests
        ) ?? automaticallyLinkPullRequests
        suppressPullRequestLinkPrompts = try container.decodeIfPresent(
            Bool.self,
            forKey: .suppressPullRequestLinkPrompts
        ) ?? suppressPullRequestLinkPrompts
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
        pullRequestGenerationPrompt = try container.decodeIfPresent(
            String.self,
            forKey: .pullRequestGenerationPrompt
        ) ?? pullRequestGenerationPrompt
        pullRequestReviewPrompt = try container.decodeIfPresent(
            String.self,
            forKey: .pullRequestReviewPrompt
        ) ?? pullRequestReviewPrompt
        pullRequestAddressFeedbackPrompt = try container.decodeIfPresent(
            String.self,
            forKey: .pullRequestAddressFeedbackPrompt
        ) ?? pullRequestAddressFeedbackPrompt
        // Absent means "follow the Threads defaults", so these stay nil rather than
        // falling back to the packaged value the way the prompts do.
        pullRequestReviewProvider = try container.decodeIfPresent(String.self, forKey: .pullRequestReviewProvider)
        pullRequestReviewModel = try container.decodeIfPresent(String.self, forKey: .pullRequestReviewModel)
        pullRequestReviewEffort = try container.decodeIfPresent(String.self, forKey: .pullRequestReviewEffort)
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
