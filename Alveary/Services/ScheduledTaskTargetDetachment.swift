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
        /// The thread's Project is being deleted in the same commit, so inherit nothing that
        /// depends on it and pause with the reason a directly-attached schedule already gets.
        case pauseForProjectDeletion(projectPath: String)
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
            definition.grantedRoots = workspace.grantedRoots
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
    /// `nil` leaves the definition's stored strategy alone — without a Project it is dead data the
    /// editor never shows.
    let strategy: ScheduledTaskWorkspaceStrategy?
    let grantedRoots: [String]
    let section: SidebarSection?

    init(thread: AgentThread, continuation: ScheduledTaskTargetDetachment.Continuation) {
        if case .pauseForProjectDeletion(let projectPath) = continuation {
            kind = .privateWorkspace
            project = nil
            strategy = nil
            grantedRoots = Self.inheritedGrantedRoots(of: thread)
                .filter { $0 != projectPath }
            section = Self.inheritedSection(of: thread)
            return
        }
        // A `.project`-mode thread with no Project cannot name one here, so it falls back to the
        // private-workspace shape rather than persisting an unsatisfiable `.project` kind.
        if thread.effectiveMode == .project, let threadProject = thread.project {
            kind = .project
            project = threadProject
            strategy = thread.useWorktree ? .worktree : .localCheckout
            grantedRoots = []
            // A Project-backed thread nests under its Project and never renders in a section.
            section = nil
            return
        }
        kind = .privateWorkspace
        project = nil
        strategy = nil
        grantedRoots = Self.inheritedGrantedRoots(of: thread)
        section = Self.inheritedSection(of: thread)
    }

    /// Copies the descriptor's roots literally — no re-canonicalization.
    ///
    /// `CanonicalPath.normalize` resolves symlinks, so normalizing here would silently rewrite a
    /// grant whose folder was replaced by a symlink since the descriptor was written, moving the
    /// user's authorization boundary without review. `TaskWorkspaceDescriptor` already stores
    /// canonical, deduplicated roots, and `ScheduledTaskMutationService.create` refuses to
    /// re-normalize for the same reason.
    private static func inheritedGrantedRoots(of thread: AgentThread) -> [String] {
        thread.taskWorkspaceDescriptor?.grantedRoots ?? []
    }

    /// Builtin membership is never persisted on a thread, but a definition may only name a custom
    /// section — matching `ScheduledTaskMutationService.validate(_:timeZoneIdentifier:)`.
    private static func inheritedSection(of thread: AgentThread) -> SidebarSection? {
        guard let section = thread.customSection, section.kind == .custom else {
            return nil
        }
        return section
    }
}
