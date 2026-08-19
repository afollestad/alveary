import Foundation
import SwiftData

/// Pre-save validation shared by `create` and `edit`, split from the mutation flows so each file
/// stays under budget: destination-shape rules and grant-literal checks.
///
/// Deliberately does not pin an existing-thread target. A schedule does not own its target's
/// sidebar placement — the user may unpin, re-section, archive, or delete that thread freely, and
/// `ScheduledTaskTargetDetachment` converts the definition when the thread goes away.
extension ScheduledTaskMutationService {
    /// Whether an edit keeps a `.reusedThread` schedule's created-thread link. The link survives
    /// only edits the existing thread can absorb: provider is fixed at conversation creation, and
    /// a workspace change must mint a fresh thread with the new configuration — the claim derives
    /// the run's workspace from the linked thread, so keeping the link would silently ignore the
    /// edit forever. Model, effort, and permission changes keep the link; materialization
    /// re-asserts them onto the thread.
    func preservesReuseLink(of definition: ScheduledTask, applying edit: ScheduledTaskDefinitionEdit) -> Bool {
        definition.decodedDestination == .reusedThread
            && edit.destination == .reusedThread
            && edit.providerID == definition.providerID
            && edit.workspaceKind == definition.workspaceKind
            && edit.workspaceStrategy == definition.workspaceStrategy
            && edit.project?.path == definition.project?.path
            && edit.grantedRoots == definition.grantedRoots
    }

    func validate(
        _ edit: ScheduledTaskDefinitionEdit,
        timeZoneIdentifier: String
    ) throws {
        switch edit.destination {
        case .reusedThread, .newThreadPerRun:
            if edit.workspaceKind == .project, edit.project == nil {
                throw ScheduledTaskMutationError.projectWorkspaceRequiresProject
            }
            guard edit.targetThread == nil else {
                throw ScheduledTaskMutationError.existingThreadRequiresAvailableThread
            }
        case .existingThread:
            guard let targetThread = edit.targetThread,
                  targetThread.archivedAt == nil,
                  !targetThread.isDraft,
                  !targetThread.isForkBootstrapPending,
                  !targetThread.hasPendingScheduledTaskWorktreeCleanup,
                  targetThread.conversations.filter(\.isMain).count == 1 else {
                throw ScheduledTaskMutationError.existingThreadRequiresAvailableThread
            }
        }
        guard ScheduledTask.normalizedUniquePaths(edit.grantedRoots) == edit.grantedRoots else {
            throw ScheduledTaskMutationError.workspaceRootsChanged
        }
        // Only custom sections may be named: `Tasks` is the nil sentinel, and a built-in row
        // would be membership the sidebar can never render.
        if let threadSection = edit.threadSection, threadSection.kind != .custom {
            throw ScheduledTaskMutationError.sectionUnavailable
        }
        if edit.destination != .existingThread,
           edit.workspaceKind == .project,
           let projectPath = edit.project?.path,
           CanonicalPath.normalize(projectPath) != projectPath {
            throw ScheduledTaskMutationError.workspaceRootsChanged
        }
        try recurrenceCalculator.validate(
            edit.recurrence,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
