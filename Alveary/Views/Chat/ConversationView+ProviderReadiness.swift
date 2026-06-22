import AgentCLIKit

extension ConversationView {
    func isSelectableComposerProvider(_ status: AgentCLIKit.AgentProviderStatus, providerID: String) -> Bool {
        ThreadDefaultResolver.isReadyProvider(
            providerID: providerID,
            settings: settingsService.current,
            status: status
        )
    }
}
