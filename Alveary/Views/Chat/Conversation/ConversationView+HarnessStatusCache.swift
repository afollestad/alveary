import AgentCLIKit
import Foundation

extension ConversationView {
    static func composerHarnessStatusCacheKey(
        projectURL: URL?,
        activeHarnessID _: String,
        settings: AppSettings
    ) -> String {
        // Discovery returns every harness. Changing the active selection must not
        // discard that loaded snapshot while an open model list updates in place.
        [
            projectURL?.path ?? "",
            settings.defaultHarness,
            settings.disabledHarnessIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    static func makeFileCompletionLoader(
        fileListManager: FileListManager,
        workingDirectory: String?,
        additionalRoots: [String] = []
    ) -> @Sendable () async -> [String] {
        {
            guard let workingDirectory else {
                return []
            }
            var seenRoots = Set<String>()
            var seenFiles = Set<String>()
            var result: [String] = []
            for root in ([workingDirectory] + additionalRoots) where seenRoots.insert(root).inserted {
                guard !Task.isCancelled else { return [] }
                let files = await fileListManager.files(for: root)
                let base = URL(fileURLWithPath: root, isDirectory: true)
                for file in files {
                    let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : base.appendingPathComponent(file)
                    let path = url.standardizedFileURL.path
                    if seenFiles.insert(path).inserted { result.append(path) }
                }
            }
            return result
        }
    }
}

struct ComposerHarnessStatusSnapshot {
    let ordering: [AgentCLIKit.AgentHarnessID]
    let statuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]
}

@MainActor
enum ComposerHarnessStatusCache {
    private static var snapshots: [String: ComposerHarnessStatusSnapshot] = [:]

    static func snapshot(for key: String) -> ComposerHarnessStatusSnapshot? {
        snapshots[key]
    }

    static func store(_ snapshot: ComposerHarnessStatusSnapshot, for key: String) {
        snapshots[key] = snapshot
    }

    #if DEBUG
    static func removeAll() {
        snapshots.removeAll()
    }
    #endif
}
