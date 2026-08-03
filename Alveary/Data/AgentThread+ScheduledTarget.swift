import Foundation

extension AgentThread {
    /// Whether a scheduled task may post into this thread.
    ///
    /// Being unpinned is not disqualifying — saving the schedule pins the target — except under a
    /// pinned project, which absorbs its children so that `SidebarViewModel.setThreadPinned`
    /// cannot pin one individually and the promised pin would silently do nothing.
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
        if !isPinned, project?.isPinned == true {
            return false
        }
        switch effectiveMode {
        case .project:
            return project != nil && project?.isPinned != true
        case .task:
            return true
        }
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
