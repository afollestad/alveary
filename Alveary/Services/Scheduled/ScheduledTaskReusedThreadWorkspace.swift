import Foundation

/// The workspace a `.reusedThread` run inherits from its already-created thread.
///
/// A reuse run after the first prepares nothing — `ScheduledTaskRun.preparedWorkspace*` stays nil
/// on it — so the descriptor comes from the thread itself: the run executes wherever the first
/// run's materialization put the thread, and the definition's config only ever changes the
/// workspace by dropping the link and minting a fresh thread. Shared by the materializer (root
/// locking) and `ScheduledTaskAutomatedWorkspaceValidator` so the derivation cannot drift.
enum ScheduledTaskReusedThreadWorkspace {
    /// `nil` — no usable primary root — is a self-heal trigger, never an error.
    @MainActor
    static func descriptor(thread: AgentThread, run: ScheduledTaskRun) -> TaskWorkspaceDescriptor? {
        switch thread.effectiveMode {
        case .task:
            return thread.taskWorkspaceDescriptor
        case .project:
            // `taskWorkspaceDescriptor`'s getter gates on `.task` mode; a project-mode thread
            // derives its descriptor from the thread's own working directory, with the strategy
            // the thread was created under rather than a `preparedWorkspace*` column this run
            // never wrote.
            guard let primaryRoot = thread.primaryWorkingDirectory else {
                return nil
            }
            return TaskWorkspaceDescriptor(
                primaryRoot: primaryRoot,
                grantedRoots: run.grantedRootsSnapshot,
                ownershipStrategy: thread.useWorktree ? .projectWorktreeOwned : .projectLocal,
                ownershipMarkerID: thread.taskWorkspaceMarkerID,
                sourceProjectPath: run.projectPathSnapshot
            )
        }
    }
}
