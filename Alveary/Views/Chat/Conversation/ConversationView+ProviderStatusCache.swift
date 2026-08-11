import AgentCLIKit
import Foundation

extension ConversationView {
    static func composerProviderStatusCacheKey(
        projectURL: URL?,
        activeProviderID _: String,
        settings: AppSettings
    ) -> String {
        // Discovery returns every provider. Changing the active selection must not
        // discard that loaded snapshot while an open model list updates in place.
        [
            projectURL?.path ?? "",
            settings.defaultProvider,
            settings.disabledProviderIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    static func makeFileCompletionLoader(
        fileListManager: FileListManager,
        workingDirectory: String?
    ) -> @Sendable () async -> [String] {
        {
            guard let workingDirectory else {
                return []
            }
            return await fileListManager.files(for: workingDirectory)
        }
    }
}

struct ComposerProviderStatusSnapshot {
    let ordering: [AgentCLIKit.AgentProviderID]
    let statuses: [AgentCLIKit.AgentProviderID: AgentCLIKit.AgentProviderStatus]
}

@MainActor
enum ComposerProviderStatusCache {
    private static var snapshots: [String: ComposerProviderStatusSnapshot] = [:]

    static func snapshot(for key: String) -> ComposerProviderStatusSnapshot? {
        snapshots[key]
    }

    static func store(_ snapshot: ComposerProviderStatusSnapshot, for key: String) {
        snapshots[key] = snapshot
    }

    #if DEBUG
    static func removeAll() {
        snapshots.removeAll()
    }
    #endif
}
