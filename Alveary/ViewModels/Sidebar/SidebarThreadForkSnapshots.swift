import Foundation
import SwiftData

struct ThreadForkSourceSnapshot {
    let threadID: PersistentIdentifier
    let projectID: PersistentIdentifier?
    let projectPath: String
    let workspaceSnapshot: WorkspaceSnapshot
    let projectBaseRef: String?
    let projectRemoteName: String?
    let isGitRepository: Bool
    let sourceConversationID: String
    let sourceHarnessID: String
    let sourceHarnessSessionID: String?
    let sourceHarnessSessionHarnessID: String?
    let sourceHarnessSessionWorkingDirectory: String?
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

    var harnessSessionActionSnapshot: HarnessSessionActionSnapshot {
        HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: sourceConversationID,
                    harnessID: sourceHarnessID,
                    harnessSessionID: sourceHarnessSessionID,
                    harnessSessionHarnessID: sourceHarnessSessionHarnessID,
                    harnessSessionWorkingDirectory: sourceHarnessSessionWorkingDirectory
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

    var harnessSessionActionSnapshot: HarnessSessionActionSnapshot {
        HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: conversationID,
                    harnessID: spawnConfig.harnessId
                )
            ],
            workingDirectory: URL(fileURLWithPath: spawnConfig.workingDirectory, isDirectory: true)
        )
    }
}
