import Foundation
import SwiftData

struct AppSettings: Codable, Sendable, Equatable {
    static let currentSettingsSchemaVersion = 1
    static let supportedProviderIDs = ["claude"]
    static let supportedPermissionModes = ["default", "plan", "acceptEdits", "auto"]
    static let defaultEffortLevel = "medium"
    static let supportedEffortLevels = ["low", "medium", "high", "xhigh", "max"]
    static let supportedModels = ["default", "opus", "sonnet", "haiku"]

    // Per-model effort overrides. Add or update entries here as models gain or
    // drop levels; any model not listed falls back to `defaultModelEffortLevels`.
    // "opus" currently tracks Opus 4.7, which added `xhigh`.
    static let defaultModelEffortLevels = ["low", "medium", "high", "max"]
    static let effortLevelsByModel: [String: [String]] = [
        "opus": ["low", "medium", "high", "xhigh", "max"]
    ]

    // Per-model preferred default. Fresh threads and coerced fallbacks should
    // land on the top-tier level the model is designed for (Opus 4.7 leans
    // into `xhigh`); models without an entry fall back to `defaultEffortLevel`.
    static let defaultEffortLevelsByModel: [String: String] = [
        "opus": "xhigh"
    ]
    static let defaultModelValue = "default"
    static let supportedThemes = ["system", "light", "dark"]
    static let defaultCodeFontFamily = "SF Mono"
    static let supportedCodeFontSizeRange = 10...24
    static let supportedChatFontSizeRange = 11...24
    static let defaultEnterBehavior = ThreadEnterDefaultBehavior.queue
    static let supportedDiffViewerWidthRange = 320.0...960.0
    static let supportedDiffViewerSplitRange = 0.25...0.75
    static let defaultDiffViewerTopSectionFraction = 0.5
    static let supportedTerminalPaneHeightRange = 240.0...560.0
    static let defaultTerminalPaneHeight = 320.0
    static let supportedMaxTerminalSessionsRange = 1...50
    static let defaultMaxTerminalSessions = 10
    static let minimumSessionHandoffWindowPercentage = 70
    static let sessionHandoffWindowPercentageStep = 5
    static let defaultSessionHandoffWindowPercentage = 90
    static let supportedHandoffPercentageRange = minimumSessionHandoffWindowPercentage...100
    static let defaultSessionHandoffPrompt = SessionHandoffPromptDefaults.defaultPrompt

    var settingsSchemaVersion = Self.currentSettingsSchemaVersion
    var defaultProvider = "claude"
    var defaultModel = Self.defaultModelValue
    var permissionMode = "default"
    var effort = Self.defaultEffortLevel
    var defaultThreadCleanupAction = ThreadCleanupAction.archive
    var defaultEnterBehavior = Self.defaultEnterBehavior
    var reopenLastThreadAndConversationOnLaunch = true
    var autoTrustProjects = false
    var createWorktreeByDefault = false
    var theme = "system"
    var codeFontFamily = Self.defaultCodeFontFamily
    var codeFontSize = 13
    var chatFontSize = 14
    var diffViewerWidth = 380.0
    var diffViewerTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var terminalPaneHeight = Self.defaultTerminalPaneHeight
    var expandTerminalWhenActionsRun = false
    var maxTerminalSessions = Self.defaultMaxTerminalSessions
    var contextManagementEnabled = true
    var sessionHandoffWindowPercentage = Self.defaultSessionHandoffWindowPercentage
    var handoffContextCustomizationEnabled = true
    var sessionHandoffPrompt = Self.defaultSessionHandoffPrompt
    var notifications = NotificationSettings()
    var branchPrefix = "alveary/"
    var worktreesBaseDirectory = "~/Documents/worktrees"
    var lastAddProjectParentFolder: String?
    var providerConfigs: [String: ProviderCustomConfig] = [:]
    var lastOpenThreadID: PersistentIdentifier?
    var lastOpenConversationID: PersistentIdentifier?

    func normalized() -> AppSettings {
        var copy = self

        copy.normalizeProviderDefaults()
        copy.normalizeThreadDefaults()
        copy.normalizeAppearanceDefaults()
        copy.normalizeLayoutDefaults()
        copy.normalizeContextManagement()
        copy.normalizeNotificationDefaults()
        copy.normalizeProviderConfigs()
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
        guard let effort,
              supportedEffortLevels.contains(effort) else {
            return defaultEffortLevel
        }

        return effort
    }

    static func supportedEffortLevels(forModel model: String?) -> [String] {
        guard let model,
              let overrides = effortLevelsByModel[model] else {
            return defaultModelEffortLevels
        }
        return overrides
    }

    static func effortLevel(_ effort: String, isSupportedByModel model: String?) -> Bool {
        supportedEffortLevels(forModel: model).contains(effort)
    }

    static func defaultEffortLevel(forModel model: String?) -> String {
        guard let model,
              let override = defaultEffortLevelsByModel[model] else {
            return defaultEffortLevel
        }
        return override
    }

    static func normalizedSessionHandoffWindowPercentage(_ percentage: Int) -> Int {
        let clamped = min(
            max(percentage, supportedHandoffPercentageRange.lowerBound),
            supportedHandoffPercentageRange.upperBound
        )
        let step = sessionHandoffWindowPercentageStep
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    private mutating func normalizeProviderDefaults() {
        if !Self.supportedProviderIDs.contains(defaultProvider) {
            defaultProvider = Self.supportedProviderIDs[0]
        }
        if !Self.supportedModels.contains(defaultModel) {
            defaultModel = Self.defaultModelValue
        }
        if !Self.supportedPermissionModes.contains(permissionMode) {
            permissionMode = "default"
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

    private mutating func normalizeWorktreesBaseDirectory() {
        let trimmedWorktreesBase = worktreesBaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        worktreesBaseDirectory = trimmedWorktreesBase.isEmpty
            ? AppSettings().worktreesBaseDirectory
            : trimmedWorktreesBase
    }
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case defaultProvider
        case defaultModel
        case permissionMode
        case effort
        case defaultThreadCleanupAction
        case defaultEnterBehavior
        case reopenLastThreadAndConversationOnLaunch
        case autoTrustProjects
        case createWorktreeByDefault
        case theme
        case codeFontFamily
        case codeFontSize
        case chatFontSize
        case diffViewerWidth
        case diffViewerTopSectionFraction
        case terminalPaneHeight
        case expandTerminalWhenActionsRun
        case maxTerminalSessions
        case contextManagementEnabled
        case sessionHandoffWindowPercentage
        case handoffContextCustomizationEnabled
        case sessionHandoffPrompt
        case notifications
        case branchPrefix
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
        try decodeAgentDefaults(from: container, legacyContainer: legacyContainer)
        try decodeAppearance(from: container)
        try decodeLayout(from: container)
        try decodeContextManagement(from: container)
        try decodeStorage(from: container, storedSchemaVersion: storedSchemaVersion)
    }

    private mutating func decodeAgentDefaults(
        from container: KeyedDecodingContainer<CodingKeys>,
        legacyContainer: KeyedDecodingContainer<LegacyCodingKeys>
    ) throws {
        defaultProvider = try container.decodeIfPresent(String.self, forKey: .defaultProvider) ?? defaultProvider
        defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? defaultModel
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? permissionMode
        effort = try container.decodeIfPresent(String.self, forKey: .effort) ?? effort
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

struct ProviderCustomConfig: Codable, Sendable, Equatable {
    var extraArgs: String?

    init(
        extraArgs: String? = nil
    ) {
        self.extraArgs = extraArgs
    }

    func normalized() -> ProviderCustomConfig? {
        let normalized = ProviderCustomConfig(
            extraArgs: extraArgs?.trimmedOrNil
        )
        return normalized.isEmpty ? nil : normalized
    }

    private var isEmpty: Bool {
        extraArgs == nil
    }
}

struct NotificationSettings: Codable, Sendable, Equatable {
    static let availableSoundNames = ["Glass", "Pop", "Tink", "Purr"]
    static let defaultSoundName = "Glass"

    var enabled = true
    var osNotifications = true
    var sound = true
    var soundName: String? = NotificationSettings.defaultSoundName
}

enum ThreadCleanupAction: String, Codable, Sendable, CaseIterable {
    case archive
    case delete

    var label: String {
        switch self {
        case .archive:
            return "Archive"
        case .delete:
            return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .archive:
            return "archivebox"
        case .delete:
            return "trash"
        }
    }
}

enum ThreadEnterDefaultBehavior: String, Codable, Sendable, CaseIterable {
    case queue
    case steer

    var label: String {
        switch self {
        case .queue:
            return "Queue"
        case .steer:
            return "Steer"
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
