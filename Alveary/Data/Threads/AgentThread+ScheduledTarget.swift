import Foundation

extension AgentThread {
    /// Whether a scheduled task may post into this thread.
    ///
    /// Pinning is deliberately irrelevant: a schedule does not own its target's sidebar placement,
    /// so an unpinned thread — including a child of a pinned project, which that project absorbs —
    /// is offered like any other. Every eligible thread already renders somewhere the user can
    /// open it, either in `Tasks`, in its own section, or under its project.
    ///
    /// Shared by the Scheduled editor's option list and the `alveary_host` thread listing so the
    /// model can only name a thread the editor would also offer.
    var isEligibleScheduledTaskTarget: Bool {
        guard archivedAt == nil,
              !isDraft,
              !isForkBootstrapPending,
              !hasPendingScheduledTaskWorktreeCleanup else {
            return false
        }
        switch effectiveMode {
        case .project:
            return project != nil
        case .task:
            return true
        }
    }

    /// Whether a `.reusedThread` schedule's next run may post into this already-created thread.
    ///
    /// False rather than throwing for an archived, drafted, forked, or cleanup-pending thread:
    /// that schedule self-heals by minting a replacement instead of blocking. Deletion needs no
    /// arm here; `.nullify` has already cleared the link.
    ///
    /// Shared with the Scheduled card and editor so neither names a thread the next claim has
    /// already decided to replace.
    var isHealthyReusedScheduledTaskTarget: Bool {
        archivedAt == nil
            && !isDraft
            && !isForkBootstrapPending
            && !hasPendingScheduledTaskWorktreeCleanup
            && primaryWorkingDirectory != nil
            && soleMainConversation != nil
    }

    /// The thread's single main conversation, whose id is how a schedule names its target.
    /// `nil` when the thread has forked into several, which no target may do.
    var soleMainConversation: Conversation? {
        let mainConversations = conversations.filter(\.isMain)
        guard mainConversations.count == 1 else {
            return nil
        }
        return mainConversations.first
    }
}
