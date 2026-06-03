import AgentCLIKit
import Foundation

struct SettingsAgentProviderEnablementSource: AgentCLIKit.AgentProviderEnablementSource {
    private let settingsService: any SettingsService

    init(settingsService: any SettingsService) {
        self.settingsService = settingsService
    }

    func isProviderEnabled(_ providerId: AgentCLIKit.AgentProviderID) async -> Bool {
        await MainActor.run {
            settingsService.current.isProviderEnabled(providerId.rawValue)
        }
    }
}
