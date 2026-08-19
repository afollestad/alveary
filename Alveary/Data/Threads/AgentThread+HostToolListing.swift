import Foundation

extension AgentThread {
    /// Whether `alveary_host`'s `list_threads` may return this thread.
    ///
    /// Narrower than `isEligibleScheduledTaskTarget` by exactly one clause: a thread ID on the
    /// wire *is* its sole main conversation's ID, so a forked thread has no handle to list — while
    /// the editor's own picker resolves that conversation separately. Defined in terms of the
    /// eligibility predicate so a listed thread can never be one scheduling would refuse.
    var isListableHostToolThread: Bool {
        isEligibleScheduledTaskTarget && soleMainConversation != nil
    }
}
