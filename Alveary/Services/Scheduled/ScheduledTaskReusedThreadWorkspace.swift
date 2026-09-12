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
    static func descriptor(thread: AgentThread) -> TaskWorkspaceDescriptor? {
        thread.resolvedWorkspaceDescriptor
    }
}
