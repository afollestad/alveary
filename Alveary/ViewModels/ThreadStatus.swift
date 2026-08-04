import Foundation

enum ThreadStatus: Sendable, Equatable {
    case busy
    case waitingForUser
    case unread
    case stopped
    case error
    case archived
}

extension Conversation {
    /// `awaitsUserDecision` covers the transcript surfaces the runtime cannot see — see
    /// `ConversationDecisionAttention`. It ranks exactly like `.waitingForUser`, so `.busy` still
    /// wins and the dot appears once work settles, and it beats `.unread`: a pending scheduled
    /// proposal marks its conversation unread, and green already means "done".
    @MainActor
    func displayStatus(runtime: ActivitySignal, awaitsUserDecision: Bool) -> ThreadStatus {
        if thread?.archivedAt != nil {
            return .archived
        }

        // Same precedence the thread-level fold below applies: busy, waiting, error, unread.
        if runtime == .busy {
            return .busy
        }
        if runtime == .waitingForUser || awaitsUserDecision {
            return .waitingForUser
        }
        if runtime == .error {
            return .error
        }
        return isUnread ? .unread : .stopped
    }
}

extension AgentThread {
    /// `awaitsUserDecisionFor` covers the transcript surfaces the runtime cannot see — see
    /// `ConversationDecisionAttention`. A decision in any conversation raises the whole thread,
    /// the same way an unread one does.
    @MainActor
    func displayStatus(
        runtimeFor: (Conversation) -> ActivitySignal,
        awaitsUserDecisionFor: (Conversation) -> Bool
    ) -> ThreadStatus {
        if archivedAt != nil {
            return .archived
        }

        var hasError = false
        var isWaitingForUser = false
        var hasUnread = false

        for conversation in conversations {
            let signal = runtimeFor(conversation)
            if signal == .busy {
                return .busy
            }
            if signal == .waitingForUser || awaitsUserDecisionFor(conversation) {
                isWaitingForUser = true
            }
            if signal == .error {
                hasError = true
            }
            if conversation.isUnread {
                hasUnread = true
            }
        }

        if isWaitingForUser {
            return .waitingForUser
        }
        if hasError {
            return .error
        }
        if hasUnread {
            return .unread
        }
        return .stopped
    }
}
