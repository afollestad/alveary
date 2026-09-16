import AgentCLIKit
import Foundation

extension ConversationView {
    var activeWorkingDirectory: String? {
        conversation.thread?.primaryWorkingDirectory
    }

    var harnessDiscoveryProjectURL: URL? {
        Self.harnessDiscoveryURL(for: conversation.thread, harnessID: activeHarnessID)
    }

    /// OpenCode's catalog follows the actual worktree configuration; a missing worktree can still expose source defaults during repair.
    static func harnessDiscoveryURL(for thread: AgentThread?, harnessID: String? = nil) -> URL? {
        guard let thread else {
            return nil
        }
        if harnessID == "opencode", let path = thread.primaryWorkingDirectory {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        let path = thread.sourceFolder?.path ?? thread.primaryWorkingDirectory
        return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var activeHarnessID: String {
        conversation.harness ?? conversation.harnessSessionHarnessId ?? settingsService.current.defaultHarness
    }

    var activeAgentHarnessID: AgentCLIKit.AgentHarnessID? {
        AgentCLIKit.AgentHarnessID(rawValue: activeHarnessID)
    }

    var activeHarnessStatus: AgentCLIKit.AgentHarnessStatus? {
        activeAgentHarnessID.flatMap { composerHarnessStatuses[$0] }
    }
}
