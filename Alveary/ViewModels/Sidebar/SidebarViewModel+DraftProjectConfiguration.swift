import Foundation

extension SidebarViewModel {
    /// Save project membership and inherited draft defaults in one synchronous transaction. Hidden setup
    /// clears `isDraft` before its first suspension, so edits cannot retarget a workspace already starting.
    func refreshProjectDraftWorkspaces(_ project: Project, changes: inout [DraftProjectWorkspaceChange]) throws {
        for draft in project.threads where draft.isDraft && !draft.hasCompletedInitialSetup
            && draft.worktreePath == nil && !draft.isForkBootstrapPending && draft.scheduledTaskRun == nil {
            guard let original = draft.workspaceSnapshot else { throw WorkspaceFolderError.invalidSnapshot }
            let primary = project.primaryFolder?.snapshot
            let grants = draft.draftHasExplicitGrants ? original.grants
                : project.orderedFolders.map(\.snapshot).filter { $0.path != primary?.path }
            let snapshot = WorkspaceSnapshot(primarySource: primary, grants: grants)
            guard snapshot != original else { continue }

            let previous = DraftWorkspaceState(thread: draft)
            let privateWorkspace = primary == nil
                ? try previous.privateWorkspace ?? taskWorkspaceOwnershipService.createPrivateWorkspace() : nil
            changes.append(DraftProjectWorkspaceChange(thread: draft, previous: previous, privateWorkspace: privateWorkspace))
            draft.mode = privateWorkspace == nil ? .project : .task
            draft.taskWorkspaceDescriptor = privateWorkspace
            draft.workspaceSnapshot = snapshot
            if privateWorkspace != nil { draft.taskGrantedRoots = snapshot.grants.map(\.path) }
            draft.useWorktree = primary?.isGitRepository == true
                && (draft.draftWorktreePreference ?? (original.primarySource?.isGitRepository == true
                    ? previous.useWorktree : settingsService.current.createWorktreeByDefault))
        }
    }
}

@MainActor
struct DraftProjectWorkspaceChange {
    let thread: AgentThread
    let previous: DraftWorkspaceState
    let privateWorkspace: TaskWorkspaceDescriptor?
}
