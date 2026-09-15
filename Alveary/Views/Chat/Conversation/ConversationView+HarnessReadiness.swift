import AgentCLIKit

extension ConversationView {
    func isSelectableComposerHarness(_ status: AgentCLIKit.AgentHarnessStatus, harnessID: String) -> Bool {
        ThreadDefaultResolver.isReadyHarness(
            harnessID: harnessID,
            settings: settingsService.current,
            status: status
        )
    }
}
