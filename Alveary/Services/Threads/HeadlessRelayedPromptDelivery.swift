import Foundation

/// Posts a prompt another thread's agent sent into an existing thread with no window mounted —
/// the delivery half of `send_prompt_to_thread`.
///
/// A sibling of `AppComponent.startHeadlessInitialPrompt` rather than a widening of it: that one
/// stays prompt-only and fire-and-forget, while this awaits the queue-or-send decision so the
/// tool can say whether the prompt started a turn or is waiting behind one. It lives off
/// `AppComponent` so the hydration and lease contract below can be exercised against a registry
/// built over a mock runtime.
@MainActor
enum HeadlessRelayedPromptDelivery {
    static func deliver(
        _ outbound: OutboundMessageText,
        into conversation: Conversation,
        registry: any ConversationControllerRegistry
    ) async throws -> RelayedPromptDelivery {
        let lease = registry.makeBackgroundLease(for: conversation)
        lease.activate()
        let viewModel = lease.viewModel

        // A controller this call just created may hold an empty grouper, and the first live
        // event would advance its incremental cursor past history it never processed — the next
        // mount's non-forced rebuild then appends that history *after* this turn. Hydrate first,
        // as the scheduled executor does before posting into an existing thread. Mid-turn the
        // controller already exists and is consistent, and a rebuild there would fight the
        // live stream, which is the same reason the transcript view skips it.
        if !viewModel.turnState.isActive {
            viewModel.rebuildChatItemsFromConversationRecords()
        }

        let delivery: RelayedPromptDelivery
        do {
            delivery = try await viewModel.queueOrSendRelayedPrompt(outbound)
        } catch {
            lease.release()
            throw error
        }

        // The lease outlives the call for the reason a created thread's first turn holds its
        // own, plus one more: a queued prompt drains only under an active controller lifecycle,
        // so releasing at the first terminal outcome — the turn it queued behind — would park it
        // until someone opened the thread. Release at the first terminal outcome that leaves the
        // queue empty.
        Task { @MainActor in
            defer { lease.release() }
            for await outcome in lease.outcomes() where outcome.state.isTerminal {
                if viewModel.messageQueue.peekNext() == nil {
                    break
                }
            }
        }
        return delivery
    }
}
