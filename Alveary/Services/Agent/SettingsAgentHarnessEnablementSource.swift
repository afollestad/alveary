import AgentCLIKit
import Foundation

struct SettingsAgentHarnessEnablementSource: AgentCLIKit.AgentHarnessEnablementSource {
    private let settingsService: any SettingsService

    init(settingsService: any SettingsService) {
        self.settingsService = settingsService
    }

    func isHarnessEnabled(_ harnessId: AgentCLIKit.AgentHarnessID) async -> Bool {
        await MainActor.run {
            settingsService.current.isHarnessEnabled(harnessId.rawValue)
        }
    }
}
