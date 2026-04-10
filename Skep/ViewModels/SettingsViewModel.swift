import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsService: any SettingsService

    init(settingsService: any SettingsService) {
        self.settingsService = settingsService
    }

    var availableProviderIDs: [String] {
        AppSettings.supportedProviderIDs
    }

    func permissionModeOptions(for providerId: String) -> [String] {
        providerId == "claude" ? AppSettings.supportedPermissionModes : []
    }

    func effortOptions(for providerId: String) -> [String] {
        providerId == "claude" ? AppSettings.supportedEffortLevels : []
    }

    var themeOptions: [String] {
        AppSettings.supportedThemes
    }

    var availableSoundNames: [String] {
        NotificationSettings.availableSoundNames
    }

    var defaultProvider: String {
        get { settingsService.current.defaultProvider }
        set { settingsService.update { $0.defaultProvider = newValue } }
    }

    var permissionMode: String {
        get { settingsService.current.permissionMode }
        set { settingsService.update { $0.permissionMode = newValue } }
    }

    var effort: String {
        get { settingsService.current.effort }
        set { settingsService.update { $0.effort = newValue } }
    }

    var autoGenerateNames: Bool {
        get { settingsService.current.autoGenerateNames }
        set { settingsService.update { $0.autoGenerateNames = newValue } }
    }

    var autoTrustWorktrees: Bool {
        get { settingsService.current.autoTrustWorktrees }
        set { settingsService.update { $0.autoTrustWorktrees = newValue } }
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
        get { settingsService.current.codeFontFamily }
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
        set { settingsService.update { $0.notifications.soundName = newValue } }
    }

    var branchPrefix: String {
        get { settingsService.current.branchPrefix }
        set { settingsService.update { $0.branchPrefix = newValue } }
    }

    var pushOnCreate: Bool {
        get { settingsService.current.pushOnCreate }
        set { settingsService.update { $0.pushOnCreate = newValue } }
    }

    func providerConfig(for providerId: String) -> ProviderCustomConfig {
        settingsService.current.providerConfigs[providerId] ?? ProviderCustomConfig()
    }

    func updateProviderConfig(for providerId: String, _ transform: (inout ProviderCustomConfig) -> Void) {
        settingsService.update { settings in
            var config = settings.providerConfigs[providerId] ?? ProviderCustomConfig()
            transform(&config)
            settings.providerConfigs[providerId] = config
        }
    }
}
