import AgentCLIKit
import Foundation

extension ConversationView {
    var activeWorkingDirectory: String? {
        conversation.thread?.primaryWorkingDirectory
    }

    var providerDiscoveryProjectURL: URL? {
        Self.providerDiscoveryURL(for: conversation.thread)
    }

    static func providerDiscoveryURL(for thread: AgentThread?) -> URL? {
        guard let thread else {
            return nil
        }
        let path = thread.effectiveMode == .project ? thread.project?.path : thread.primaryWorkingDirectory
        return path.map { URL(fileURLWithPath: CanonicalPath.normalize($0), isDirectory: true) }
    }

    var activeProviderID: String {
        conversation.provider ?? settingsService.current.defaultProvider
    }

    var activeAgentProviderID: AgentCLIKit.AgentProviderID? {
        AgentCLIKit.AgentProviderID(rawValue: activeProviderID)
    }

    var activeProviderStatus: AgentCLIKit.AgentProviderStatus? {
        activeAgentProviderID.flatMap { composerProviderStatuses[$0] }
    }
}
