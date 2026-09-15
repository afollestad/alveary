import AgentCLIKit
import Foundation

extension ConversationView {
    var activeWorkingDirectory: String? {
        conversation.thread?.primaryWorkingDirectory
    }

    var harnessDiscoveryProjectURL: URL? {
        Self.harnessDiscoveryURL(for: conversation.thread)
    }

    static func harnessDiscoveryURL(for thread: AgentThread?) -> URL? {
        guard let thread else {
            return nil
        }
        let path = thread.sourceFolder?.path ?? thread.primaryWorkingDirectory
        return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var activeHarnessID: String {
        conversation.harness ?? settingsService.current.defaultHarness
    }

    var activeAgentHarnessID: AgentCLIKit.AgentHarnessID? {
        AgentCLIKit.AgentHarnessID(rawValue: activeHarnessID)
    }

    var activeHarnessStatus: AgentCLIKit.AgentHarnessStatus? {
        activeAgentHarnessID.flatMap { composerHarnessStatuses[$0] }
    }
}
