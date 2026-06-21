import Foundation

extension ConversationViewModel {
    func hydratePendingRestoreContextIfNeeded() {
        guard let pendingRestoreContext = dbConversation()?.pendingRestoreContext else {
            return
        }

        if state.stagedContext == pendingRestoreContext {
            return
        }

        guard !state.messageQueue.pending.contains(where: { $0.stagedContext == pendingRestoreContext }) else {
            return
        }

        state.stagedContext = pendingRestoreContext
    }

    func clearConsumedPendingRestoreContext(using stagedContext: String?) {
        guard let stagedContext,
              let dbConversation = dbConversation(),
              dbConversation.pendingRestoreContext == stagedContext else {
            return
        }

        dbConversation.pendingRestoreContext = nil
        do {
            try modelContext.save()
        } catch {
            // Best-effort only; the next save will retry persisting the cleared restore context.
        }
    }

    func clearConsumedPendingRestoreContext(_ resolvedContext: SessionRecoveryStagedContext) {
        guard let consumedCurrentStagedContext = resolvedContext.consumedCurrentStagedContext else {
            return
        }
        clearConsumedPendingRestoreContext(using: consumedCurrentStagedContext)
    }
}
