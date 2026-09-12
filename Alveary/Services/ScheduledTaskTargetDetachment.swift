import Foundation

/// Converts every `.existingThread` schedule targeting a thread into a `.reusedThread` schedule,
/// inside the caller's own save.
///
/// A schedule does not own the thread it was pointed at: archiving or deleting that thread is a
/// user action the schedule must survive, not one it may refuse. So the lifecycle commit calls
/// this immediately before it writes `archivedAt` or deletes the row, while the thread is still
/// fully readable, and the schedule falls back to the self-healing reuse mode that mints its own
/// replacement thread on the next run.
///
/// Deliberately performs no `save()` of its own — the flip must land in the same transaction as
/// the lifecycle mutation that caused it, or a failed archive would leave a retargeted schedule
/// behind. It returns the changed definition IDs so the caller can publish
/// `.scheduledTasksChanged` only after its commit succeeds.
@MainActor
enum ScheduledTaskTargetDetachment {
    /// What the surviving schedule does next.
    enum Continuation {
        /// Keep the cadence and inherit the lost thread's workspace.
        case reuseInheritedWorkspace
        /// Remove sidebar placement and pause while preserving the frozen source and grants.
        case pauseForProjectDeletion
    }

    /// - Returns: the IDs of the definitions this changed, for the caller to publish after saving.
    @discardableResult
    static func detachTargets(
        of thread: AgentThread,
        continuation: Continuation = .reuseInheritedWorkspace,
        at actionDate: Date = .now
    ) -> [String] {
        // Only a decodable existing-thread row is converted. `.newThreadPerRun` ignores the link
        // entirely, and an unknown raw value must keep it: that undecodable string is exactly what
        // makes `invalidDefinitionReason` pause the definition instead of running it, and
        // overwriting it with `.reusedThread` would hand a forward-version row a workspace and let
        // it execute. `.nullify` still clears the dangling link on delete.
        let definitions = thread.targetedScheduledTasks.filter {
            $0.decodedDestination == .existingThread
        }
        guard !definitions.isEmpty else {
            return []
        }
        let workspace = InheritedWorkspace(thread: thread, continuation: continuation)
        for definition in definitions {
            definition.targetThread = nil
            definition.destination = .reusedThread
            // A stale link would make the next claim post into a thread this definition never
            // created; nil is what tells the materializer to mint one.
            definition.reusedThread = nil
            definition.workspaceKind = workspace.kind
            definition.project = workspace.project
            if let strategy = workspace.strategy {
                definition.workspaceStrategy = strategy
            }
            definition.grantedRoots = workspace.snapshot?.grants.map(\.path) ?? []
            definition.workspaceSnapshot = workspace.snapshot
            definition.threadSection = workspace.section
            switch continuation {
            case .reuseInheritedWorkspace:
                definition.targetWaitStartedAt = nil
                // Safe to bump: archive and delete quiesce an attached run before committing, so
                // no live run's revision check can lose a race with this write.
                definition.revision += 1
                definition.modifiedAt = actionDate
            case .pauseForProjectDeletion:
                definition.pauseForProjectDeletion(at: actionDate)
            }
        }
        return definitions.map(\.id)
    }
}

/// The workspace a flipped schedule adopts, read off the thread before it goes away.
///
/// A Task's own `primaryRoot` is deliberately not carried: it is the private workspace being torn
/// down. Its granted roots are the closest representable equivalent, so the replacement thread
/// keeps the same folder access.
private struct InheritedWorkspace {
    let kind: ScheduledTaskWorkspaceKind
    let project: Project?
    let strategy: ScheduledTaskWorkspaceStrategy?
    let snapshot: WorkspaceSnapshot?
    let section: SidebarSection?

    init(thread: AgentThread, continuation: ScheduledTaskTargetDetachment.Continuation) {
        // Owned workspaces are being removed. Retain their source repository and every grant,
        // so the next run can create a replacement from the same frozen configuration.
        snapshot = thread.workspaceSnapshot
        kind = snapshot?.primarySource == nil ? .privateWorkspace : .project
        let ownsWorktree = thread.resolvedWorkspaceDescriptor?.ownershipStrategy == .projectWorktreeOwned
        strategy = kind == .project ? (thread.useWorktree || ownsWorktree ? .worktree : .localCheckout) : nil
        switch continuation {
        case .reuseInheritedWorkspace: project = thread.project
        case .pauseForProjectDeletion: project = nil
        }
        section = project == nil && thread.customSection?.kind == .custom ? thread.customSection : nil
    }
}
