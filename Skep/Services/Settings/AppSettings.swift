import Foundation

struct AppSettings: Codable, Sendable, Equatable {
    static let supportedProviderIDs = ["claude"]
    static let supportedPermissionModes = ["default", "plan", "acceptEdits", "auto", "bypassPermissions"]
    static let supportedEffortLevels = ["low", "medium", "high", "max"]
    static let supportedThemes = ["system", "light", "dark"]

    var defaultProvider = "claude"
    var permissionMode = "default"
    var effort = "medium"
    var autoGenerateNames = true
    var autoTrustWorktrees = true
    var createWorktreeByDefault = false
    var theme = "system"
    var codeFontFamily = "SF Mono"
    var codeFontSize = 13
    var chatFontSize = 14
    var notifications = NotificationSettings()
    var branchPrefix = "skep"
    var pushOnCreate = false
    var providerConfigs: [String: ProviderCustomConfig] = [:]

    func normalized() -> AppSettings {
        var copy = self

        if !Self.supportedProviderIDs.contains(copy.defaultProvider) {
            copy.defaultProvider = Self.supportedProviderIDs[0]
        }
        if !Self.supportedPermissionModes.contains(copy.permissionMode) {
            copy.permissionMode = "default"
        }
        if !Self.supportedEffortLevels.contains(copy.effort) {
            copy.effort = "medium"
        }
        if !Self.supportedThemes.contains(copy.theme) {
            copy.theme = "system"
        }
        if let soundName = copy.notifications.soundName,
           !NotificationSettings.availableSoundNames.contains(soundName) {
            copy.notifications.soundName = NotificationSettings.defaultSoundName
        }
        copy.providerConfigs = copy.providerConfigs.reduce(into: [:]) { partialResult, entry in
            if let normalized = entry.value.normalized() {
                partialResult[entry.key] = normalized
            }
        }

        return copy
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

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
