import Foundation
import SwiftData

struct AppSettings: Codable, Sendable, Equatable {
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
    static let supportedDiffViewerWidthRange = 320.0...960.0
    static let supportedDiffViewerSplitRange = 0.25...0.75
    static let defaultDiffViewerTopSectionFraction = 0.5
    static let supportedTerminalPaneHeightRange = 240.0...560.0
    static let defaultTerminalPaneHeight = 320.0

    var defaultProvider = "claude"
    var defaultModel = Self.defaultModelValue
    var permissionMode = "default"
    var effort = Self.defaultEffortLevel
    var deleteKeyAction = ThreadDeleteKeyAction.archive
    var reopenLastThreadAndConversationOnLaunch = false
    var autoTrustProjects = true
    var createWorktreeByDefault = false
    var theme = "system"
    var codeFontFamily = Self.defaultCodeFontFamily
    var codeFontSize = 13
    var chatFontSize = 14
    var diffViewerWidth = 380.0
    var diffViewerTopSectionFraction = Self.defaultDiffViewerTopSectionFraction
    var terminalPaneHeight = Self.defaultTerminalPaneHeight
    var notifications = NotificationSettings()
    var branchPrefix = "alveary"
    var worktreesBaseDirectory = "~/Documents/worktrees"
    var lastAddProjectParentFolder: String?
    var providerConfigs: [String: ProviderCustomConfig] = [:]
    var lastOpenThreadID: PersistentIdentifier?
    var lastOpenConversationID: PersistentIdentifier?

    func normalized() -> AppSettings {
        var copy = self

        if !Self.supportedProviderIDs.contains(copy.defaultProvider) {
            copy.defaultProvider = Self.supportedProviderIDs[0]
        }
        if !Self.supportedModels.contains(copy.defaultModel) {
            copy.defaultModel = Self.defaultModelValue
        }
        if !Self.supportedPermissionModes.contains(copy.permissionMode) {
            copy.permissionMode = "default"
        }
        copy.effort = Self.normalizedEffortLevel(copy.effort)
        if !Self.supportedThemes.contains(copy.theme) {
            copy.theme = "system"
        }
        copy.diffViewerWidth = min(
            max(copy.diffViewerWidth, Self.supportedDiffViewerWidthRange.lowerBound),
            Self.supportedDiffViewerWidthRange.upperBound
        )
        copy.diffViewerTopSectionFraction = min(
            max(copy.diffViewerTopSectionFraction, Self.supportedDiffViewerSplitRange.lowerBound),
            Self.supportedDiffViewerSplitRange.upperBound
        )
        copy.terminalPaneHeight = min(
            max(copy.terminalPaneHeight, Self.supportedTerminalPaneHeightRange.lowerBound),
            Self.supportedTerminalPaneHeightRange.upperBound
        )
        if let soundName = copy.notifications.soundName,
           !NotificationSettings.availableSoundNames.contains(soundName) {
            copy.notifications.soundName = NotificationSettings.defaultSoundName
        }
        copy.providerConfigs = copy.providerConfigs.reduce(into: [:]) { partialResult, entry in
            if let normalized = entry.value.normalized() {
                partialResult[entry.key] = normalized
            }
        }

        let trimmedWorktreesBase = copy.worktreesBaseDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.worktreesBaseDirectory = trimmedWorktreesBase.isEmpty
            ? AppSettings().worktreesBaseDirectory
            : trimmedWorktreesBase

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
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case defaultProvider
        case defaultModel
        case permissionMode
        case effort
        case deleteKeyAction
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
        case notifications
        case branchPrefix
        case worktreesBaseDirectory
        case lastAddProjectParentFolder
        case providerConfigs
        case lastOpenThreadID
        case lastOpenConversationID
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case autoTrustWorktrees
    }

    init(from decoder: any Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        self.defaultProvider = try container.decodeIfPresent(String.self, forKey: .defaultProvider) ?? defaults.defaultProvider
        self.defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? defaults.defaultModel
        self.permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? defaults.permissionMode
        self.effort = try container.decodeIfPresent(String.self, forKey: .effort) ?? defaults.effort
        self.deleteKeyAction = try container.decodeIfPresent(ThreadDeleteKeyAction.self, forKey: .deleteKeyAction) ?? defaults.deleteKeyAction
        self.reopenLastThreadAndConversationOnLaunch = try container.decodeIfPresent(
            Bool.self,
            forKey: .reopenLastThreadAndConversationOnLaunch
        ) ?? defaults.reopenLastThreadAndConversationOnLaunch
        self.autoTrustProjects = try container.decodeIfPresent(Bool.self, forKey: .autoTrustProjects)
            ?? legacyContainer.decodeIfPresent(Bool.self, forKey: .autoTrustWorktrees)
            ?? defaults.autoTrustProjects
        self.createWorktreeByDefault = try container.decodeIfPresent(Bool.self, forKey: .createWorktreeByDefault) ?? defaults.createWorktreeByDefault
        self.theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
        self.codeFontFamily = try container.decodeIfPresent(String.self, forKey: .codeFontFamily) ?? defaults.codeFontFamily
        self.codeFontSize = try container.decodeIfPresent(Int.self, forKey: .codeFontSize) ?? defaults.codeFontSize
        self.chatFontSize = try container.decodeIfPresent(Int.self, forKey: .chatFontSize) ?? defaults.chatFontSize
        self.diffViewerWidth = try container.decodeIfPresent(Double.self, forKey: .diffViewerWidth) ?? defaults.diffViewerWidth
        self.diffViewerTopSectionFraction = try container.decodeIfPresent(
            Double.self,
            forKey: .diffViewerTopSectionFraction
        ) ?? defaults.diffViewerTopSectionFraction
        self.terminalPaneHeight = try container.decodeIfPresent(Double.self, forKey: .terminalPaneHeight) ?? defaults.terminalPaneHeight
        self.notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? defaults.notifications
        self.branchPrefix = try container.decodeIfPresent(String.self, forKey: .branchPrefix) ?? defaults.branchPrefix
        self.worktreesBaseDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .worktreesBaseDirectory
        ) ?? defaults.worktreesBaseDirectory
        self.lastAddProjectParentFolder = try container.decodeIfPresent(
            String.self,
            forKey: .lastAddProjectParentFolder
        )
        self.providerConfigs = try container.decodeIfPresent(
            [String: ProviderCustomConfig].self,
            forKey: .providerConfigs
        ) ?? defaults.providerConfigs
        self.lastOpenThreadID = try? container.decodeIfPresent(PersistentIdentifier.self, forKey: .lastOpenThreadID)
        self.lastOpenConversationID = try? container.decodeIfPresent(PersistentIdentifier.self, forKey: .lastOpenConversationID)
    }
}

struct ProviderCustomConfig: Codable, Sendable, Equatable {
    var cli: String?
    var resumeFlag: String?
    var defaultArgs: String?
    var autoApproveFlag: String?
    var initialPromptFlag: String?
    var extraArgs: String?
    var env: [String: String]?

    init(
        cli: String? = nil,
        resumeFlag: String? = nil,
        defaultArgs: String? = nil,
        autoApproveFlag: String? = nil,
        initialPromptFlag: String? = nil,
        extraArgs: String? = nil,
        env: [String: String]? = nil
    ) {
        self.cli = cli
        self.resumeFlag = resumeFlag
        self.defaultArgs = defaultArgs
        self.autoApproveFlag = autoApproveFlag
        self.initialPromptFlag = initialPromptFlag
        self.extraArgs = extraArgs
        self.env = env
    }

    func normalized() -> ProviderCustomConfig? {
        let normalizedEnv = env?.reduce(into: [String: String]()) { partialResult, entry in
            guard let key = entry.key.trimmedOrNil,
                  let value = entry.value.trimmedOrNil else {
                return
            }
            partialResult[key] = value
        }
        let normalized = ProviderCustomConfig(
            cli: cli?.trimmedOrNil,
            resumeFlag: resumeFlag?.trimmedOrNil,
            defaultArgs: defaultArgs?.trimmedOrNil,
            autoApproveFlag: autoApproveFlag?.trimmedOrNil,
            initialPromptFlag: initialPromptFlag?.trimmedOrNil,
            extraArgs: extraArgs?.trimmedOrNil,
            env: normalizedEnv?.isEmpty == true ? nil : normalizedEnv
        )
        return normalized.isEmpty ? nil : normalized
    }

    private var isEmpty: Bool {
        cli == nil &&
            resumeFlag == nil &&
            defaultArgs == nil &&
            autoApproveFlag == nil &&
            initialPromptFlag == nil &&
            extraArgs == nil &&
            (env?.isEmpty ?? true)
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

enum ThreadDeleteKeyAction: String, Codable, Sendable, CaseIterable {
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
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
