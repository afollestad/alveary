import Foundation

/// Handles target loss inside the caller's lifecycle transaction. Exact callbacks retain their
/// identity and pause; legacy schedules inherit the old workspace and adopt self-healing reuse.
/// Performs no save: publish the returned IDs only after the lifecycle commit succeeds.
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
            if definition.exactTargetConversationID != nil {
                pauseExactCallback(definition, at: actionDate)
                continue
            }
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

    /// Tab removal changes only schedules aimed at that exact tab, in the deleting transaction.
    static func pauseCallbacks(to conversation: Conversation, at date: Date = .now) -> [String] {
        let definitions = conversation.thread?.targetedScheduledTasks.filter {
            $0.decodedDestination == .existingThread && $0.exactTargetConversationID == conversation.id
        } ?? []
        for definition in definitions { pauseExactCallback(definition, at: date) }
        return definitions.map(\.id)
    }

    private static func pauseExactCallback(_ definition: ScheduledTask, at date: Date) {
        guard definition.state != .completed else { return }
        definition.state = .paused
        definition.nextOccurrenceAt = nil
        definition.pendingOccurrenceAt = nil
        definition.targetWaitStartedAt = nil
        definition.pauseReason = "The callback conversation was removed or archived. Choose an available target before resuming."
        definition.revision += 1
        definition.modifiedAt = date
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
