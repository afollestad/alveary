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
    static let supportedRightPaneWidthRange = 320.0...960.0
    static let supportedDiffViewerWidthRange = supportedRightPaneWidthRange
    static let supportedDiffViewerSplitRange = 0.25...0.75
    static let defaultDiffViewerTopSectionFraction = 0.5
    static let defaultDiffViewerMode = DiffViewerMode.currentChanges
    static let supportedTerminalPaneHeightRange = 240.0...560.0
    static let defaultTerminalPaneHeight = 320.0
    static let supportedMaxTerminalSessionsRange = 1...50
    static let defaultMaxTerminalSessions = 10
    static let defaultAppShotShortcut = AppShotKeyboardShortcut.controlShiftS
    static let defaultVoiceInputShortcut = PhysicalKeyboardShortcut.controlShiftSpace
    static let fallbackVoiceInputShortcut = PhysicalKeyboardShortcut.controlCommandShiftSpace
    var settingsSchemaVersion = Self.currentSettingsSchemaVersion
    var hasCompletedOnboarding = false
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
    var skillsPaneWidth = 380.0
    var mcpPaneWidth = 380.0
    var scheduledTasksPaneWidth = 380.0
    var pullRequestsPaneWidth = 460.0
    // The sidebar row is the only entry point to the Pull Requests screen, so hiding it
    // removes the screen entirely.
    var showsPullRequestsInSidebar = true
    var diffViewerTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerCommitsTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerMode = Self.defaultDiffViewerMode
    var terminalPaneHeight = Self.defaultTerminalPaneHeight
    var expandTerminalWhenActionsRun = false
    var maxTerminalSessions = Self.defaultMaxTerminalSessions
    var appShotsEnabled = true
    var appShotShortcut = Self.defaultAppShotShortcut
    var voiceInputShortcut: PhysicalKeyboardShortcut? = Self.defaultVoiceInputShortcut
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
    var lastActiveProjectPath: String?
    var lastOpenThreadID: PersistentIdentifier?
    var lastOpenConversationID: PersistentIdentifier?
    var voiceInputShortcutMigrationCompleted = true
    // Raw tab titles; each screen falls back to its packaged default when the
    // stored value no longer names a tab.
    var pullRequestsSelectedTab = "All"
    var scheduledTasksSelectedTab = "All"
    var pullRequestsStatusFilters: Set<PullRequestStatus> = []
    var pullRequestsRepositoryFilters: Set<String> = []

    func normalized() -> AppSettings {
        var copy = self

        copy.normalizeProviderDefaults()
        copy.normalizeThreadDefaults()
        copy.turnAwake = copy.turnAwake.normalized()
        copy.normalizeAppearanceDefaults()
        copy.normalizeLayoutDefaults()
        copy.normalizeAppShotDefaults()
        copy.normalizeVoiceInputShortcut()
        copy.normalizeContextManagement()
        copy.normalizeNotificationDefaults()
        copy.normalizeProviderConfigs()
        copy.normalizeGitDefaults()
        copy.normalizeWorktreesBaseDirectory()
        copy.normalizeLastActiveProjectPath()
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
        skillsPaneWidth = Self.normalizedRightPaneWidth(skillsPaneWidth)
        mcpPaneWidth = Self.normalizedRightPaneWidth(mcpPaneWidth)
        scheduledTasksPaneWidth = Self.normalizedRightPaneWidth(scheduledTasksPaneWidth)
        pullRequestsPaneWidth = Self.normalizedRightPaneWidth(pullRequestsPaneWidth)
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

}
