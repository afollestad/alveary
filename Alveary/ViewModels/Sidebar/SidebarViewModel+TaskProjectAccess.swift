import Foundation
import SwiftData

/// Everything the confirmation dialog needs, captured synchronously at drop time so the sheet can
/// describe the grant without re-reading models across the user's decision.
struct SidebarTaskProjectAccessRequest: Equatable {
    let threadID: PersistentIdentifier
    let projectID: PersistentIdentifier
    let threadName: String
    let projectName: String
    let projectKey: String
    var folderPaths: [String] = []
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
        guard thread.supportsIndependentSidebarPlacement else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "Only independently placed threads can move into a project"
            )
        }
        guard !thread.isDraft, !thread.isForkBootstrapPending, thread.archivedAt == nil else {
            throw SidebarViewModelError.taskProjectAccessUnavailable(
                "This Task cannot be given folder access right now"
            )
        }
        guard let workspace = thread.resolvedWorkspaceDescriptor else {
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
        let grantsNewAccess = project.orderedFolders.contains { !alreadyGrants(workspace: workspace, projectPath: $0.path) }
        if grantsNewAccess, let definition = thread.blockingWorkspaceGrantScheduledTask {
            throw SidebarViewModelError.scheduledTaskAttachment(definition.title)
        }

        return SidebarTaskProjectAccessRequest(
            threadID: threadID,
            projectID: projectID,
            threadName: thread.displayName(),
            projectName: project.name,
            projectKey: project.id,
            folderPaths: project.orderedFolders.map(\.path),
            restartsAgentProcess: thread.hasCompletedInitialSetup,
            grantsNewAccess: grantsNewAccess
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
              let workspace = thread.resolvedWorkspaceDescriptor else {
            throw SidebarViewModelError.threadMissingTaskWorkspace
        }

        guard let snapshot = thread.workspaceSnapshot else { throw WorkspaceFolderError.invalidSnapshot }
        let additionalFolders = project.orderedFolders.map(\.snapshot).filter { $0.path != workspace.primaryRoot }
        for folder in additionalFolders where !workspace.grantedRoots.contains(folder.path) {
            _ = try WorkspaceFolderTarget(directory: folder.path, source: folder, isPrimary: false).requireDirectory()
        }
        let conversationIDs = thread.conversations.map(\.id)

        try flushPendingChangesBeforeTaskProjectAccess()
        do {
            try thread.replaceAdditionalFolders(
                snapshot.grants + additionalFolders,
                rootsExplicitlyManaged: request.grantsNewAccess || snapshot.rootsExplicitlyManaged
            )
            // Only placement changes; execution and cleanup retain the saved workspace.
            thread.project = project
            // The project owns where its children render, so the drop clears any standalone pin.
            // Keeping it would leave the Task a project child that still draws its own row under
            // `Pinned`; a pinned project would absorb the child outright and the pin could never
            // take effect at all. Pinning afterwards still promotes it back out.
            thread.isPinned = false
            thread.pinnedSortOrder = nil
            // Project placement supersedes custom-section membership; normalization would clear
            // it anyway, but doing it here keeps the invariant visible at the mutation.
            thread.customSection = nil
            thread.modifiedAt = Date()
            _ = try normalizeSidebarOrderingForLifecycle()
            try savePendingSidebarChanges(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        NotificationCenter.default.post(name: .workspaceConfigurationChanged, object: nil)
        refreshThreadOrder(animated: true)

        // A live process was launched without the new root, so retire it non-destructively. Suspend
        // preserves the provider session and binding, letting the next turn resume with history.
        for conversationID in conversationIDs {
            await agentsManager.suspendRuntime(conversationId: conversationID)
        }
    }
}

private extension SidebarViewModel {
    func alreadyGrants(workspace: TaskWorkspaceDescriptor, projectPath: String) -> Bool {
        workspace.primaryRoot == projectPath || workspace.grantedRoots.contains(projectPath)
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
