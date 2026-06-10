import AgentCLIKit
import Foundation

extension ConversationView {
    var activeWorkingDirectory: String? {
        conversation.thread?.worktreePath ?? conversation.thread?.project?.path
    }

    var providerDiscoveryProjectURL: URL? {
        conversation.thread?.project.map { URL(fileURLWithPath: CanonicalPath.normalize($0.path), isDirectory: true) }
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
