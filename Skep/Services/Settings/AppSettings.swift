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
}

struct NotificationSettings: Codable, Sendable, Equatable {
    static let availableSoundNames = ["Glass", "Pop", "Tink", "Purr"]
    static let defaultSoundName = "Glass"

    var enabled = true
    var osNotifications = true
    var sound = true
    var soundName: String? = NotificationSettings.defaultSoundName
}
