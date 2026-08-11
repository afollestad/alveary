import Foundation

extension AgentThread {
    /// Unanswered transcript link prompts, oldest first. Storage semantics live in
    /// `PendingPullRequestPromptStorage`.
    var pendingPullRequestLinkPrompts: [PendingPullRequestPrompt] {
        get { PendingPullRequestPromptStorage.decode(pendingPullRequestPromptsJSON) }
        set { pendingPullRequestPromptsJSON = PendingPullRequestPromptStorage.encode(newValue) }
    }

    func hasPendingPullRequestPrompt(for identifier: PullRequestIdentifier) -> Bool {
        pendingPullRequestLinkPrompts.contains { $0.identifier == identifier }
    }

    /// Whether one conversation still shows an unanswered link question.
    ///
    /// Answers `contains` rather than `!prompts.isEmpty` because it runs per conversation per
    /// sidebar body. The `nil` check is load-bearing for the same reason: both accessors it
    /// reaches decode a JSON column on every call, and almost every thread stores nothing here.
    /// Callers must still apply the `pullRequestsEnabled` / `suppressPullRequestLinkPrompts`
    /// settings gates.
    func hasUnansweredPullRequestLinkPrompt(conversationID: String) -> Bool {
        guard pendingPullRequestPromptsJSON != nil else {
            return false
        }
        return pendingPullRequestLinkPrompts.contains {
            isUnansweredPullRequestLinkPrompt($0, conversationID: conversationID)
        }
    }

    /// One conversation's unanswered link questions, oldest first.
    func unansweredPullRequestLinkPrompts(conversationID: String) -> [PendingPullRequestPrompt] {
        pendingPullRequestLinkPrompts
            .filter { isUnansweredPullRequestLinkPrompt($0, conversationID: conversationID) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Already-linked prompts are filtered rather than removed, so a stale entry cannot resurrect
    /// a question. The transcript rows and the sidebar's waiting dot both come through here so
    /// they cannot disagree about what counts as unanswered.
    private func isUnansweredPullRequestLinkPrompt(
        _ prompt: PendingPullRequestPrompt,
        conversationID: String
    ) -> Bool {
        prompt.conversationID == conversationID && !isPullRequestLinked(prompt.identifier)
    }
}
