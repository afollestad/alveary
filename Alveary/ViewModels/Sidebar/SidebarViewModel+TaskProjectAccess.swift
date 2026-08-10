import Foundation
import SwiftData

/// Everything the confirmation dialog needs, captured synchronously at drop time so the sheet can
/// describe the grant without re-reading models across the user's decision.
struct SidebarTaskProjectAccessRequest: Equatable {
    let threadID: PersistentIdentifier
    let projectID: PersistentIdentifier
    let threadName: String
    let projectName: String
    let projectPath: String
    /// False when the running agent picks the folder up only on its next turn, because its process
    /// was launched without it.
    let restartsAgentProcess: Bool
    /// False when the Task can already reach this folder, which makes the drop pure placement.
    let grantsNewAccess: Bool
}

extension SidebarViewModel {
    /// Cheap synchronous eligibility check, run at drop time before the confirmation dialog and
    /// again inside `moveTaskIntoProject` because anything here can change while it is up.
    @discardableResult
    func validateTaskProjectAccess(
        threadID: PersistentIdentifier,
        projectID: PersistentIdentifier
    ) throws -> SidebarTaskProjectAccessRequest {
        guard let thread = modelContext.resolveThread(id: threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        guard let project = modelContext.resolveProject(id: projectID) else {
            throw SidebarViewModelError.projectMissing
        }
        guard thread.effectiveMode == .task else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "Only Tasks can be given access to a project folder"
            )
        }
        guard !thread.isDraft, !thread.isForkBootstrapPending, thread.archivedAt == nil else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "This Task cannot be given folder access right now"
            )
        }
        guard let workspace = thread.taskWorkspaceDescriptor else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }
        // Each conversation launches its own provider process, so a multi-conversation Task would
        // need every one restarted. Refuse instead, matching composer-driven grant editing.
        guard thread.conversations.count == 1 else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "A Task can only be given folder access while it has one conversation"
            )
        }
        try requireNoScheduledTaskAttachment(thread)
        guard thread.project?.persistentModelID != projectID else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "This Task is already in \(project.name)"
            )
        }
        try requireTaskProjectAccessIsIdle(thread)

        return SidebarTaskProjectAccessRequest(
            threadID: threadID,
            projectID: projectID,
            threadName: thread.displayName(),
            projectName: project.name,
            projectPath: project.path,
            restartsAgentProcess: thread.hasCompletedInitialSetup,
            grantsNewAccess: !alreadyGrants(workspace: workspace, projectPath: project.path)
        )
    }

    /// Adds a project's folder to a Task's workspace grants.
    ///
    /// The Task stays a Task — it keeps its own workspace, its provider session, and its Task-mode
    /// behavior — but it now renders as one of the project's children and can reach that folder.
    /// Because the working directory is untouched, the provider resumes its existing session, so
    /// history survives; the runtime is only suspended so the next turn relaunches with the new root.
    func moveTaskIntoProject(
        _ threadID: PersistentIdentifier,
        projectID: PersistentIdentifier
    ) async throws {
        let request = try validateTaskProjectAccess(threadID: threadID, projectID: projectID)
        guard let thread = modelContext.resolveThread(id: threadID),
              let project = modelContext.resolveProject(id: projectID),
              let workspace = thread.taskWorkspaceDescriptor else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }

        let grantedRoots: [String]
        do {
            grantedRoots = try taskWorkspaceOwnershipService.canonicalizeGrants(
                workspace.grantedRoots + [request.projectPath],
                excludingPrimaryRoot: workspace.primaryRoot
            )
        } catch {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "\(request.projectName) could not be granted: \(error.localizedDescription)"
            )
        }

        try flushPendingChangesBeforeTaskProjectAccess()
        do {
            thread.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
                primaryRoot: workspace.primaryRoot,
                grantedRoots: grantedRoots,
                ownershipStrategy: workspace.ownershipStrategy,
                ownershipMarkerID: workspace.ownershipMarkerID,
                sourceProjectPath: workspace.sourceProjectPath
            )
            // Placement only. Mode stays `.task`, so the working directory, cleanup, and diff
            // routing all keep reading the Task's own workspace.
            thread.project = project
            // The project owns where its children render, so the drop clears any standalone pin.
            // Keeping it would leave the Task a project child that still draws its own row under
            // `Pinned`; a pinned project would absorb the child outright and the pin could never
            // take effect at all. Pinning afterwards still promotes it back out.
            thread.isPinned = false
            thread.pinnedSortOrder = nil
            thread.modifiedAt = Date()
            _ = try normalizeSidebarOrderingForLifecycle()
            try savePendingSidebarChanges(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        refreshThreadOrder(animated: true)

        // A live process was launched without the new root, so retire it non-destructively. Suspend
        // preserves the provider session and binding, letting the next turn resume with history.
        for conversationID in thread.conversations.map(\.id) {
            await agentsManager.suspendRuntime(conversationId: conversationID)
        }
    }
}

private extension SidebarViewModel {
    /// A path already reachable from the workspace needs no new grant. Canonicalization can fail
    /// for a missing folder; the move itself rejects that case with a clearer message.
    func alreadyGrants(workspace: TaskWorkspaceDescriptor, projectPath: String) -> Bool {
        guard let canonical = try? taskWorkspaceOwnershipService.canonicalizeGrants(
            [projectPath],
            excludingPrimaryRoot: workspace.primaryRoot
        ) else {
            return false
        }
        // An empty result means the path resolved to the workspace's own root, already reachable.
        guard let target = canonical.first else {
            return true
        }
        return workspace.grantedRoots.contains(target)
    }

    func requireTaskProjectAccessIsIdle(_ thread: AgentThread) throws {
        for conversation in thread.conversations {
            switch agentsManager.status(for: conversation.id) {
            case .busy:
                throw SidebarViewModelError.taskProjectAccessUnavailable(
                    "Wait for this Task to finish before changing its folder access"
                )
            case .waitingForUser:
                throw SidebarViewModelError.taskProjectAccessUnavailable(
                    "Resolve this Task's pending prompt before changing its folder access"
                )
            case .neutral, .idle, .stopped, .error:
                continue
            }
        }
        guard !hasUnresolvedApproval(conversationIDs: thread.conversations.map(\.id)) else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "Approve or deny this Task's pending tool use before changing its folder access"
            )
        }
    }

    func flushPendingChangesBeforeTaskProjectAccess() throws {
        guard modelContext.hasChanges else {
            return
        }
        try savePendingSidebarChanges(modelContext)
    }
}
