import Foundation
import SwiftData

@MainActor
extension AppDelegate {
    func retainedPrivateWorkspaceMarkerIDs(
        excluding threadIDs: Set<PersistentIdentifier>,
        modelContext: ModelContext
    ) throws -> Set<String> {
        let threadMarkerIDs = try modelContext.fetch(FetchDescriptor<AgentThread>()).compactMap { thread -> String? in
            guard !threadIDs.contains(thread.persistentModelID),
                  thread.effectiveMode == .task,
                  thread.taskWorkspaceOwnershipStrategyRawValue == TaskWorkspaceOwnershipStrategy.privateOwned.rawValue,
                  let root = thread.taskPrimaryRoot else {
                return nil
            }
            return normalizedWorkspaceMarkerID(thread.taskWorkspaceMarkerID)
                ?? normalizedWorkspaceMarkerID(URL(fileURLWithPath: root, isDirectory: true).lastPathComponent)
        }
        let preparedRunMarkerIDs = try modelContext.fetch(FetchDescriptor<ScheduledTaskRun>()).compactMap { run -> String? in
            let hasRetainedTask = run.thread.map { !threadIDs.contains($0.persistentModelID) } == true
            guard !run.hasKnownTerminalStatus || hasRetainedTask,
                  ScheduledTaskWorkspaceKind(rawValue: run.workspaceKindRawValueSnapshot) == .privateWorkspace,
                  run.preparedWorkspaceOwnershipStrategy == .privateOwned,
                  let root = run.preparedWorkspaceRoot else {
                return nil
            }
            return normalizedWorkspaceMarkerID(run.preparedWorkspaceMarkerID)
                ?? normalizedWorkspaceMarkerID(URL(fileURLWithPath: root, isDirectory: true).lastPathComponent)
        }
        return Set(threadMarkerIDs + preparedRunMarkerIDs)
    }

    private func normalizedWorkspaceMarkerID(_ markerID: String?) -> String? {
        guard let markerID,
              let uuid = UUID(uuidString: markerID),
              uuid.uuidString.lowercased() == markerID.lowercased() else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }
}
