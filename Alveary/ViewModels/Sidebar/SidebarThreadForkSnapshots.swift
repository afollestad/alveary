import Foundation
import SwiftData

struct ThreadForkSourceSnapshot {
    let threadID: PersistentIdentifier
    let projectID: PersistentIdentifier
    let projectPath: String
    let projectBaseRef: String?
    let projectRemoteName: String?
    let isGitRepository: Bool
    let sourceConversationID: String
    let sourceProviderID: String
    let sourceProviderSessionID: String?
    let sourceProviderSessionProviderID: String?
    let sourceProviderSessionWorkingDirectory: String?
    let sourceWorkingDirectory: String
    let threadConversationIDs: [String]
    let threadName: String
    let permissionMode: String
    let planModeEnabled: Bool
    let effort: String
    let model: String?
    let speedMode: AgentSpeedMode
    let mode: SidebarThreadForkMode

    var conversationIDs: [String] {
        threadConversationIDs.isEmpty ? [sourceConversationID] : threadConversationIDs
    }

    var providerSessionActionSnapshot: ProviderSessionActionSnapshot {
        ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: sourceConversationID,
                    providerID: sourceProviderID,
                    providerSessionID: sourceProviderSessionID,
                    providerSessionProviderID: sourceProviderSessionProviderID,
                    providerSessionWorkingDirectory: sourceProviderSessionWorkingDirectory
                )
            ],
            workingDirectory: URL(fileURLWithPath: sourceWorkingDirectory, isDirectory: true)
        )
    }
}

struct ForkCreatedWorktree {
    let info: WorktreeInfo
    let expectedStatus: String?
}

struct ForkWorktreeBase {
    let baseRef: String?
    let remoteName: String?
}

struct ThreadForkTargetSnapshot {
    let threadID: PersistentIdentifier
    let conversationID: String
    let projectPath: String
    let worktree: ForkCreatedWorktree?
    let spawnConfig: AgentSpawnConfig

    var providerSessionActionSnapshot: ProviderSessionActionSnapshot {
        ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: conversationID,
                    providerID: spawnConfig.providerId
                )
            ],
            workingDirectory: URL(fileURLWithPath: spawnConfig.workingDirectory, isDirectory: true)
        )
    }
}
