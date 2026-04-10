actor DefaultProviderSetupService: ProviderSetupService {
    private let claudeConfigStore: ClaudeConfigStore

    init(claudeConfigStore: ClaudeConfigStore) {
        self.claudeConfigStore = claudeConfigStore
    }

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        switch providerId {
        case "claude":
            await claudeConfigStore.ensureLocalSettingsFile(in: workingDirectory)
            if autoTrust {
                await claudeConfigStore.upsertTrustedProject(path: workingDirectory)
            }
        default:
            break
        }
    }
}
