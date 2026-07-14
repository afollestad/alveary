import Foundation
import SwiftData

struct ScheduledTaskRunMaterialization: Sendable {
    let runID: PersistentIdentifier
    let threadID: PersistentIdentifier
    let conversationID: String
    let prompt: String
    let workspace: TaskWorkspaceDescriptor
}

@MainActor
protocol ScheduledTaskRunMaterializing: AnyObject {
    func materialize(runID: PersistentIdentifier) async throws -> ScheduledTaskRunMaterialization
}

enum ScheduledTaskRunMaterializationError: LocalizedError {
    case runMissing
    case invalidRunStatus(ScheduledTaskRunStatus)
    case invalidTimeZone(String)
    case invalidWorkspaceConfiguration(kind: String, strategy: String)
    case missingProjectPath
    case missingWorkspaceIdentityProvenance
    case projectWorkspaceMissing(String)
    case workspaceRootsChanged
    case missingWorktreeCleanupMetadata
    case worktreeCleanupSourceChanged(String)
    case runChangedDuringPreparation
    case provenancePersistenceFailed(Error)
    case preparationAndCleanupFailed(preparation: Error, cleanup: Error)

    var errorDescription: String? {
        switch self {
        case .runMissing:
            return "The scheduled task run no longer exists."
        case .invalidRunStatus(let status):
            return "The scheduled task run cannot be prepared from its current status: \(status.rawValue)."
        case .invalidTimeZone(let identifier):
            return "The scheduled task uses an invalid timezone: \(identifier)."
        case let .invalidWorkspaceConfiguration(kind, strategy):
            return "The scheduled task uses an invalid workspace configuration: \(kind)/\(strategy)."
        case .missingProjectPath:
            return "The scheduled task run is missing its Project workspace path."
        case .missingWorkspaceIdentityProvenance:
            return "The scheduled task run is missing its claimed workspace identity."
        case .projectWorkspaceMissing(let path):
            return "The scheduled task Project workspace is unavailable: \(path)."
        case .workspaceRootsChanged:
            return "The scheduled task workspace or folder access changed after the run was claimed."
        case .missingWorktreeCleanupMetadata:
            return "The scheduled task worktree is missing cleanup metadata."
        case .worktreeCleanupSourceChanged(let path):
            return "Git cleanup was deferred because the scheduled task Project directory changed: \(path)"
        case .runChangedDuringPreparation:
            return "The scheduled task run changed while its workspace was being prepared."
        case .provenancePersistenceFailed(let error):
            return "The scheduled task could not save its Task history: \(error.localizedDescription)"
        case let .preparationAndCleanupFailed(preparation, cleanup):
            return "Scheduled task preparation failed (\(preparation.localizedDescription)), and workspace cleanup also failed: " +
                cleanup.localizedDescription
        }
    }
}

struct ScheduledTaskOccurrenceNoteFormatter {
    let locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func text(occurrenceAt: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Scheduled task for \(formatter.string(from: occurrenceAt))"
    }
}
