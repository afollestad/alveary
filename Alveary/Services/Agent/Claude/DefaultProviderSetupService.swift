actor DefaultProviderSetupService: ProviderSetupService {
    private let claudeConfigStore: ClaudeConfigStore

    init(claudeConfigStore: ClaudeConfigStore) {
        self.claudeConfigStore = claudeConfigStore
    }

    nonisolated func cachedProjectTrustStatus(providerId: String, workingDirectory: String) -> Bool? {
        switch providerId {
        case "claude":
            claudeConfigStore.cachedSnapshot().isTrustedProject(path: workingDirectory)
        default:
            true
        }
    }

    func prepareForSpawn(providerId: String, workingDirectory: String, autoTrust: Bool) async {
        switch providerId {
        case "claude":
            if autoTrust {
                await claudeConfigStore.upsertTrustedProject(path: workingDirectory)
            }
        default:
            break
        }
    }

    func isTrustedProject(providerId: String, workingDirectory: String) async -> Bool {
        switch providerId {
        case "claude":
            await claudeConfigStore.isTrustedProject(path: workingDirectory)
        default:
            true
        }
    }

    func trustProject(providerId: String, workingDirectory: String) async {
        switch providerId {
        case "claude":
            await claudeConfigStore.upsertTrustedProject(path: workingDirectory)
        default:
            break
        }
    }
}
