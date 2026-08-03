import SwiftData
import SwiftUI

/// Opens the thread a transcript card names, where the thread-management widgets live.
/// Only the root owns sidebar selection, so the request arrives as a notification.
extension ContentView {
    func handleThreadOpenRequest(_ notification: Notification) {
        guard let request = notification.userInfo?[
            ThreadOpenRequestNotificationKey.request
        ] as? ThreadOpenRequest else {
            return
        }
        openTranscriptThreadInAppState(
            conversationId: request.conversationID,
            modelContext: uiModelContext,
            appState: appState
        )
    }
}

/// Selects a thread named by one of its own transcript cards.
///
/// An archived thread has no sidebar row to select, so its card lands on the screen that does
/// list it and can bring it back; `openConversationInAppState` would silently ignore it.
@MainActor
func openTranscriptThreadInAppState(
    conversationId: String,
    modelContext: ModelContext,
    appState: AppState
) {
    guard let conversation = modelContext.resolveConversation(conversationID: conversationId),
          let thread = conversation.thread,
          !thread.isDraft else {
        return
    }
    guard thread.archivedAt == nil else {
        appState.selectedSidebarItem = .archived
        return
    }
    openConversationInAppState(
        conversationId: conversationId,
        modelContext: modelContext,
        appState: appState
    )
}
