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
}
