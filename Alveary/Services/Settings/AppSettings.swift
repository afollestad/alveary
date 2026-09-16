import Foundation
import SwiftData

enum PullRequestReviewMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case singleAgent
    case reviewTeam
}

struct PullRequestReviewPeer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var harnessID: String
    var model: String
    var effort: String

    /// Keep the stored JSON format stable across the harness terminology rename.
    private enum CodingKeys: String, CodingKey {
        case id
        case harnessID = "providerID"
        case model
        case effort
    }
}

struct AppSettings: Codable, Sendable, Equatable {
    static let currentSettingsSchemaVersion = 1
    static let supportedHarnessIDs = ["claude", "codex", "opencode"]
    static let supportedPermissionModesByHarness = [
        "claude": ["default", "acceptEdits", "auto", "bypassPermissions"],
        "codex": ["untrusted", "on-request", "never"],
        "opencode": ["configured", "ask", "fullAccess"]
    ]
    static let supportedPermissionModes = [
        "default", "acceptEdits", "auto", "bypassPermissions", "untrusted", "on-request", "never", "configured", "ask", "fullAccess"
    ]
    static let defaultPermissionModeByHarness = [
        "claude": "default",
        "codex": "on-request",
        "opencode": "ask"
    ]
    static let defaultEffortLevel = "medium"
    static let defaultModelValue = "default"
    /// Picker-only inheritance must stay distinct from native names, including OpenCode variants.
    static let inheritedSelectionValue = "alveary.inherit"
    static let supportedThemes = ["system", "light", "dark"]
    static let defaultCodeFontFamily = "SF Mono"
    static let supportedCodeFontSizeRange = 10...24
    static let supportedChatFontSizeRange = 11...24
    static let defaultEnterBehavior = ThreadEnterDefaultBehavior.queue
    static let supportedRightPaneWidthRange = 320.0...960.0
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
    var lastSettingsPage = SettingsPage.harnesses
    var defaultHarness = "claude"
    var defaultModel = Self.defaultModelValue
    var permissionMode = "default"
    var effort = Self.defaultEffortLevel
    /// Nil follows thread defaults; explicit utility pins survive unavailable or unsupported harnesses for repair.
    var utilityHarness: String?
    var utilityModel: String?
    var utilityEffort: String?
    var disabledHarnessIDs: Set<String> = []
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
    // One width for the whole right-pane lane. Per-destination widths made the
    // main pane resize whenever the lane switched panes, which re-wrapped chat
    // bubbles that the user had not touched.
    var rightPaneWidth = 380.0
    // Gates the whole pull-request integration: the sidebar row that leads to the
    // Pull Requests screen, and the thread toolbar's linked-pull-request button.
    var pullRequestsEnabled = true
    // Links pull requests found in new transcript messages without asking.
    var automaticallyLinkPullRequests = false
    // Written only by the transcript link prompt's `Never` action; deliberately has
    // no settings row, so re-enabling prompts happens by turning auto-linking on.
    var suppressPullRequestLinkPrompts = false
    var diffViewerTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerCommitsTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var diffViewerMode = Self.defaultDiffViewerMode
    var terminalPaneHeight = Self.defaultTerminalPaneHeight
    var expandTerminalWhenActionsRun = false
    var maxTerminalSessions = Self.defaultMaxTerminalSessions
    var showsMenuBarIcon = true
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
    var pullRequestGenerationPrompt = Self.defaultPullRequestGenerationPrompt
    var pullRequestReviewPrompt = Self.defaultPullRequestReviewPrompt
    var pullRequestAddressFeedbackPrompt = Self.defaultPullRequestAddressFeedbackPrompt
    var pullRequestReviewMode = PullRequestReviewMode.singleAgent
    var pullRequestReviewPeers: [PullRequestReviewPeer] = []
    /// Review pins also configure the team lead; nil follows the Threads defaults.
    var pullRequestReviewHarness: String?
    var pullRequestReviewModel: String?
    var pullRequestReviewEffort: String?
    /// Used by single-agent reviews only; team workers always run read-only.
    var pullRequestReviewPermissionMode: String?
    var pullRequestAddressFeedbackHarness: String?
    var pullRequestAddressFeedbackModel: String?
    var pullRequestAddressFeedbackEffort: String?
    var pullRequestAddressFeedbackPermissionMode: String?
    /// Encoding this marker keeps cleared feedback pins from inheriting legacy review pins again.
    var pullRequestAgentSettingsVersion = 1
    /// `SidebarSection.id` of the custom section each agentic route's spawned thread joins; nil
    /// is the plain `Tasks` list. A bare id with no relationship behind it — unlike
    /// `ScheduledTask.threadSection` nothing nullifies it when the section is removed, so every
    /// reader degrades to `Tasks` rather than failing.
    var pullRequestAddressFeedbackSectionID: String?
    var pullRequestReviewSectionID: String?
    var gitCommitIncludeUnstagedChanges = true
    var worktreesBaseDirectory = "~/Documents/worktrees"
    var lastAddProjectParentFolder: String?
    var lastActiveProjectID: String?
    /// Legacy selection, retained until it resolves to an unambiguous membership.
    var lastActiveProjectPath: String?
    var lastOpenThreadID: PersistentIdentifier?
    var lastOpenConversationID: PersistentIdentifier?
    var voiceInputShortcutMigrationCompleted = true
    // Raw tab titles; each screen falls back to its packaged default when the
    // stored value no longer names a tab.
    var pullRequestsSelectedTab = "All"
    var scheduledTasksSelectedTab = "All"
    // Raw `PullRequestReviewFooterAction.Kind`, one per authorship, because the two halves of a
    // pull request's life want opposite defaults. A stored value that no longer names a kind
    // falls back to the default beside it.
    var pullRequestOwnFooterActionKind = "addressFeedback"
    var pullRequestOthersFooterActionKind = "agenticReview"
    /// Single-select because it is pushed into the GitHub search, where qualifiers only AND —
    /// see `PullRequestStatusFilter`. The packaged default keeps "needs my review" free of
    /// merged, closed, and draft pull requests.
    var pullRequestsStatusFilter: PullRequestStatusFilter = .open
    var pullRequestsRepositoryFilters: Set<String> = []

    func normalized() -> AppSettings {
        var copy = self

        copy.normalizeHarnessDefaults()
        copy.normalizeThreadDefaults()
        copy.turnAwake = copy.turnAwake.normalized()
        copy.normalizeAppearanceDefaults()
        copy.normalizeLayoutDefaults()
        copy.normalizeAppShotDefaults()
        copy.normalizeVoiceInputShortcut()
        copy.normalizeContextManagement()
        copy.normalizeNotificationDefaults()
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

    static func supportedPermissionModes(forHarness harnessID: String) -> [String] {
        supportedPermissionModesByHarness[harnessID] ?? []
    }

    static func defaultPermissionMode(forHarness harnessID: String) -> String {
        defaultPermissionModeByHarness[harnessID] ?? "default"
    }

    func isHarnessEnabled(_ harnessID: String) -> Bool {
        Self.supportedHarnessIDs.contains(harnessID) && !disabledHarnessIDs.contains(harnessID)
    }

    mutating func setHarness(_ harnessID: String, enabled: Bool) {
        guard Self.supportedHarnessIDs.contains(harnessID) else {
            return
        }
        if enabled {
            disabledHarnessIDs.remove(harnessID)
        } else {
            disabledHarnessIDs.insert(harnessID)
        }
    }

    private mutating func normalizeHarnessDefaults() {
        disabledHarnessIDs = Set(disabledHarnessIDs.filter(Self.supportedHarnessIDs.contains))
        if disabledHarnessIDs.count >= Self.supportedHarnessIDs.count,
           let fallbackHarness = Self.supportedHarnessIDs.first {
            disabledHarnessIDs.remove(fallbackHarness)
        }

        if !Self.supportedHarnessIDs.contains(defaultHarness) {
            defaultHarness = Self.supportedHarnessIDs[0]
        }
        // Keep a disabled OpenCode choice visible for recovery instead of silently switching its model provider.
        if defaultHarness != "opencode", !isHarnessEnabled(defaultHarness),
           let fallbackHarness = Self.supportedHarnessIDs.first(where: { isHarnessEnabled($0) }) {
            defaultHarness = fallbackHarness
        }

        defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if defaultModel.isEmpty {
            defaultModel = Self.defaultModelValue
        }

        if !Self.supportedPermissionModes(forHarness: defaultHarness).contains(permissionMode) {
            permissionMode = Self.defaultPermissionMode(forHarness: defaultHarness)
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
        rightPaneWidth = Self.normalizedRightPaneWidth(rightPaneWidth)
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

    private mutating func normalizeGitDefaults() {
        if commitMessageGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitMessageGenerationPrompt = Self.defaultCommitMessageGenerationPrompt
        }
        if pullRequestGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pullRequestGenerationPrompt = Self.defaultPullRequestGenerationPrompt
        }
        if pullRequestReviewPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pullRequestReviewPrompt = Self.defaultPullRequestReviewPrompt
        }
        if pullRequestAddressFeedbackPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pullRequestAddressFeedbackPrompt = Self.defaultPullRequestAddressFeedbackPrompt
        }
        normalizePullRequestAgentDefaults()
    }

    /// Drop unknown harness and permission values; creation validates compatibility with the
    /// resolved harness, which may differ from an unavailable pin. Section existence needs SwiftData.
    private mutating func normalizePullRequestAgentDefaults() {
        pullRequestReviewAgent = Self.normalizedPullRequestAgent(pullRequestReviewAgent)
        pullRequestAddressFeedbackAgent = Self.normalizedPullRequestAgent(pullRequestAddressFeedbackAgent)
        pullRequestAddressFeedbackSectionID = Self.normalizedOptionalSetting(pullRequestAddressFeedbackSectionID)
        pullRequestReviewSectionID = Self.normalizedOptionalSetting(pullRequestReviewSectionID)
    }

    private static func normalizedPullRequestAgent(_ value: PullRequestAgentSettings) -> PullRequestAgentSettings {
        var result = value
        result.harness = normalizedOptionalSetting(value.harness)
            .flatMap { Self.supportedHarnessIDs.contains($0) ? $0 : nil }
        result.model = normalizedOptionalSetting(value.model)
        result.effort = normalizedOptionalSetting(value.effort)
        result.permissionMode = normalizedOptionalSetting(value.permissionMode)
            .flatMap { Self.supportedPermissionModes.contains($0) ? $0 : nil }
        return result
    }

    private static func normalizedOptionalSetting(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private mutating func normalizeWorktreesBaseDirectory() {
        let trimmedWorktreesBase = worktreesBaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        worktreesBaseDirectory = trimmedWorktreesBase.isEmpty
            ? AppSettings().worktreesBaseDirectory
            : trimmedWorktreesBase
    }

}
