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
    /// From `ConversationWorkActivity.isWorking(_:)` — app-side work the runtime cannot report.
    let isWorking: Bool
    /// `Conversation.lastTurnFailedAt != nil` — the durable half of `.error`, since the runtime's
    /// own signal lives only in `DefaultAgentsManager.statusSnapshot`.
    let lastTurnFailed: Bool
}

extension ConversationStatusSnapshot {
    /// Declared in an extension so the synthesized memberwise initializer survives for tests.
    ///
    /// Neither collaborator takes a default: a surface that folded statuses without one would
    /// silently lose an indicator rather than fail to build, and there are only two call sites.
    @MainActor
    init(
        conversation: Conversation,
        attention: ConversationDecisionAttention,
        activity: ConversationWorkActivity
    ) {
        self.init(
            conversationID: conversation.id,
            isUnread: conversation.isUnread,
            awaitsUserDecision: attention.awaitsDecision(conversation),
            isWorking: activity.isWorking(conversation.id),
            lastTurnFailed: conversation.lastTurnFailedAt != nil
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
    /// `isWorking` is the same idea for app-side work — see `ConversationWorkActivity` — and ranks
    /// exactly like `.busy`, so a conversation both publishing and awaiting a decision spins rather
    /// than showing the dot behind it.
    ///
    /// `lastTurnFailed` is the durable half of `.error`, and it deliberately outranks that
    /// conversation's own `.busy`. Nothing records it without a turn ending, and
    /// `markVisibleTurnStarted()` clears it, so a flag that is still set proves no turn has begun
    /// since — which makes a `.busy` alongside it a signal a dead process never released. A
    /// *sibling* conversation that is genuinely working still spins the whole row.
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

        var fold = ThreadStatusFold()
        for conversation in conversations {
            fold.add(conversation, signal: runtimeFor(conversation.conversationID))
        }
        return fold.status
    }
}

/// Accumulates the fold one snapshot at a time. Split out of `folded` so neither half carries the
/// whole precedence ladder's branching; `status` is the ladder, `add` is the per-conversation read.
private struct ThreadStatusFold {
    private var hasLiveBusy = false
    private var hasError = false
    private var isWaitingForUser = false
    private var hasUnread = false

    mutating func add(_ conversation: ConversationStatusSnapshot, signal: ActivitySignal) {
        if conversation.lastTurnFailed {
            hasError = true
        } else if signal == .busy {
            hasLiveBusy = true
        }
        // Deliberately outside that chain, unlike the runtime's `.busy`: the suppression above
        // exists because a runtime signal outliving a failed turn proves a dead process never
        // released it, while this span is work the app itself opened and `confirm`'s `defer`
        // closes, so it is live whatever the last turn did.
        if conversation.isWorking {
            hasLiveBusy = true
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

    var status: ThreadStatus {
        if hasLiveBusy {
            return .busy
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
