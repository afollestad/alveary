import SwiftData

/// The thread-row liveness gate and the render-path booleans derived from it, split out of
/// `ThreadDetailView.swift` to keep that file inside the length limit.
extension ThreadDetailView {
    /// The thread re-resolved against the store, or `nil` once its row is gone.
    ///
    /// `thread` is a selection token handed down from `AppState`. Mounting with
    /// `.id(thread.persistentModelID)` keeps a *different* thread from reusing this view, but
    /// nothing re-fetches this one, so a delete this window did not route away from leaves `body`
    /// reading a removed row and trapping inside SwiftData. Every persisted read in the render path
    /// goes through here; `ThreadPlaceholderView` gates the same way.
    var liveThread: AgentThread? {
        modelContext.resolveThread(id: thread.persistentModelID)
    }

    func shouldShowConversationStrip(conversationCount: Int) -> Bool {
        ConversationStripPresentation.shouldShow(
            hasCompletedInitialSetup: liveThread?.hasCompletedInitialSetup == true,
            conversationCount: conversationCount
        )
    }

    var canCreateConversationFromEmptyState: Bool {
        guard let liveThread else {
            return false
        }
        return !liveThread.isDraft && liveThread.hasCompletedInitialSetup
    }

    var canPersistEmptyConversationSelection: Bool {
        guard let liveThread else {
            return false
        }
        return !liveThread.isDraft && liveThread.archivedAt == nil
    }
}

enum ConversationStripPresentation {
    static func shouldShow(hasCompletedInitialSetup: Bool, conversationCount: Int) -> Bool {
        hasCompletedInitialSetup && conversationCount > 1
    }
}
