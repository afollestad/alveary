import Foundation

extension ScheduledTask {
    /// Explicit identities never fall back, including after tab deletion or a fork.
    var resolvedTargetConversation: Conversation? {
        guard decodedDestination == .existingThread else { return nil }
        return Self.resolveTargetConversation(in: targetThread, exactID: exactTargetConversationID)
    }

    static func resolveTargetConversation(in thread: AgentThread?, exactID: String?) -> Conversation? {
        guard let thread, thread.isEligibleScheduledTaskTarget else { return nil }
        if let exactID {
            return thread.conversations.first { $0.id == exactID }
        }
        return thread.soleMainConversation
    }
}
