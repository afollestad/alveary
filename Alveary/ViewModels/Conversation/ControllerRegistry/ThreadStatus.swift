import Foundation

enum ThreadStatus: Sendable, Equatable {
    case busy
    case waitingForUser
    case unread
    case stopped
    case error
    case archived
}

/// Persisted per-conversation status inputs, snapshotted while the body pass that builds them
/// still holds live rows.
///
/// Status used to be derived by walking `thread.conversations` inside SwiftUI bodies. A body can
/// re-run after a delete commits — from its own `@State`, a revision bump, or `List` animating
/// the row out — and a persisted-property read there traps inside SwiftData with
/// `_assertionFailure`. Value types cannot, so every render-path status fold consumes these
/// instead of models.
struct ConversationStatusSnapshot: Equatable {
    let conversationID: String
    let isUnread: Bool
    /// From `ConversationDecisionAttention.awaitsDecision(_:)`, evaluated at snapshot time while
    /// the row is known live — see that function's contract.
    let awaitsUserDecision: Bool
}

extension ConversationStatusSnapshot {
    /// Declared in an extension so the synthesized memberwise initializer survives for tests.
    @MainActor
    init(conversation: Conversation, attention: ConversationDecisionAttention) {
        self.init(
            conversationID: conversation.id,
            isUnread: conversation.isUnread,
            awaitsUserDecision: attention.awaitsDecision(conversation)
        )
    }
}

extension ThreadStatus {
    /// Folds one thread's conversation snapshots into the status its sidebar row or tab chip
    /// shows. A single-element array is the per-conversation (tab chip) form; the precedence is
    /// identical either way: archived, then busy, waiting, error, unread, stopped.
    ///
    /// `awaitsUserDecision` covers the transcript surfaces the runtime cannot see — see
    /// `ConversationDecisionAttention`. It ranks exactly like `.waitingForUser`, so `.busy` still
    /// wins and the dot appears once work settles, and it beats `.unread`: a pending scheduled
    /// proposal marks its conversation unread, and green already means "done".
    ///
    /// `runtimeFor` stays a closure because runtime signals are in-memory coordinator state, not
    /// persisted rows; it is keyed by `Conversation.id` so no model crosses the fold's boundary.
    static func folded(
        isArchived: Bool,
        conversations: [ConversationStatusSnapshot],
        runtimeFor: (String) -> ActivitySignal
    ) -> ThreadStatus {
        if isArchived {
            return .archived
        }

        var hasError = false
        var isWaitingForUser = false
        var hasUnread = false

        for conversation in conversations {
            let signal = runtimeFor(conversation.conversationID)
            if signal == .busy {
                return .busy
            }
            if signal == .waitingForUser || conversation.awaitsUserDecision {
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
