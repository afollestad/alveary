import Foundation

extension AgentThread {
    /// Whether `alveary_host`'s `list_threads` may return this thread.
    ///
    /// Broader than `isEligibleScheduledTaskTarget`: a child of a pinned project is listed here,
    /// because listing does not promise a pin the way a schedule's existing-thread target does.
    /// `propose_scheduled_task` re-checks its own eligibility, so the two cannot drift into
    /// letting the model name a thread scheduling would refuse.
    var isListableHostToolThread: Bool {
        guard archivedAt == nil,
              !isDraft,
              !isForkBootstrapPending,
              !hasPendingScheduledTaskWorktreeCleanup,
              soleMainConversation != nil else {
            return false
        }
        switch effectiveMode {
        case .project:
            return project != nil
        case .task:
            return true
        }
    }
}
