import Foundation
import SwiftData

/// Creation placement is independent of execution mode. Empty projects use a private workspace.
enum ThreadDraftDestination: Equatable {
    case project(id: String)
    case tasks
    case section(id: String)

    var projectID: String? {
        if case .project(let id) = self { return id }
        return nil
    }

    @MainActor
    init(thread: AgentThread) {
        if let project = thread.project {
            self = .project(id: project.id)
        } else if let section = thread.customSection {
            self = .section(id: section.id)
        } else {
            self = .tasks
        }
    }
}

extension SidebarViewModel {
    func moveDraftThread(_ draft: AgentThread, to destination: ThreadDraftDestination) throws -> AgentThread {
        guard draft.isDraft, !draft.hasCompletedInitialSetup, draft.worktreePath == nil else {
            throw SidebarViewModelError.threadMissing
        }
        let project = try draftDestinationProject(destination)
        let section = try draftDestinationSection(destination)
        // Reopening the same draft must preserve its edited grants. Project edits refresh defaults separately.
        if draft.project?.id == project?.id, draft.customSection?.id == section?.id {
            pendingDraftDestination = destination
            if let project { settingsService.updateLastActiveProjectID(project.id) }
            return draft
        }
        let snapshot = project?.workspaceSnapshot() ?? WorkspaceSnapshot(primarySource: nil)
        let previous = DraftWorkspaceState(thread: draft)

        // Save shared-context changes before this transaction can fail; composer state belongs to the same conversation.
        if modelContext.hasChanges { try modelContext.save() }
        let privateWorkspace = snapshot.primarySource == nil
            ? try previous.privateWorkspace ?? taskWorkspaceOwnershipService.createPrivateWorkspace() : nil
        draft.project = project
        draft.customSection = section
        draft.mode = privateWorkspace == nil ? .project : .task
        draft.taskWorkspaceDescriptor = privateWorkspace
        draft.workspaceSnapshot = snapshot
        draft.draftHasExplicitGrants = false
        draft.useWorktree = snapshot.primarySource?.isGitRepository == true
            && (draft.draftWorktreePreference ?? (previous.snapshot?.primarySource?.isGitRepository == true
                ? previous.useWorktree : settingsService.current.createWorktreeByDefault))
        do {
            try persistDraftProjectMove()
        } catch {
            previous.restore(draft)
            pendingDraftDestination = ThreadDraftDestination(thread: draft)
            if let privateWorkspace, privateWorkspace.primaryRoot != previous.privateWorkspace?.primaryRoot {
                releaseDraftWorkspace(privateWorkspace)
            }
            throw error
        }
        if let oldWorkspace = previous.privateWorkspace, oldWorkspace.primaryRoot != privateWorkspace?.primaryRoot {
            releaseDraftWorkspace(oldWorkspace)
        }
        pendingDraftDestination = destination
        if let project { settingsService.updateLastActiveProjectID(project.id) }
        publishDraftWorkspaceChanged(
            draft,
            placementChanged: previous.project?.id != project?.id || previous.section?.id != section?.id
        )
        return draft
    }

    /// Workspace refreshes still update root consumers, but only actual placement changes reveal and animate sidebar rows.
    func publishDraftWorkspaceChanged(_ draft: AgentThread, placementChanged: Bool = false) {
        var userInfo: [String: Any] = [
            ThreadDraftNotificationKey.placementChanged: placementChanged,
            ThreadDraftNotificationKey.threadID: draft.persistentModelID,
            ThreadDraftNotificationKey.mode: draft.mode.rawValue
        ]
        if let project = draft.project { userInfo[ThreadDraftNotificationKey.projectID] = project.id }
        NotificationCenter.default.post(name: .threadDraftProjectChanged, object: nil, userInfo: userInfo)
    }
}

private extension SidebarViewModel {
    func draftDestinationProject(_ destination: ThreadDraftDestination) throws -> Project? {
        guard case .project(let id) = destination else { return nil }
        guard let project = modelContext.resolveProject(projectID: id) else { throw SidebarViewModelError.projectMissing }
        return project
    }

    func draftDestinationSection(_ destination: ThreadDraftDestination) throws -> SidebarSection? {
        guard case .section(let id) = destination else { return nil }
        guard let section = modelContext.resolveSidebarSection(id: id), section.kind == .custom else {
            throw SidebarSectionServiceError.sectionMissing
        }
        return section
    }
}

extension SidebarViewModel {
    func releaseDraftWorkspace(_ workspace: TaskWorkspaceDescriptor) {
        Task { [self] in
            do { try await removePrivateOwnedTaskWorkspace(workspace) } catch { presentSidebarError(error) }
        }
    }
}

@MainActor
struct DraftWorkspaceState {
    let project: Project?
    let section: SidebarSection?
    let mode: AgentThreadMode
    let workspace: TaskWorkspaceDescriptor?
    let snapshotJSON: String?
    let useWorktree: Bool
    let hasExplicitGrants: Bool

    init(thread: AgentThread) {
        project = thread.project
        section = thread.customSection
        mode = thread.mode
        workspace = thread.taskWorkspaceDescriptor
        snapshotJSON = thread.workspaceSnapshotJSON
        useWorktree = thread.useWorktree
        hasExplicitGrants = thread.draftHasExplicitGrants
    }

    var snapshot: WorkspaceSnapshot? { WorkspaceSnapshot.decode(snapshotJSON) }
    var privateWorkspace: TaskWorkspaceDescriptor? {
        workspace?.ownershipStrategy == .privateOwned ? workspace : nil
    }

    func restore(_ thread: AgentThread) {
        thread.project = project
        thread.customSection = section
        thread.mode = mode
        thread.taskWorkspaceDescriptor = workspace
        thread.workspaceSnapshotJSON = snapshotJSON
        thread.useWorktree = useWorktree
        thread.draftHasExplicitGrants = hasExplicitGrants
    }
}
