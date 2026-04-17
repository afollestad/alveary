import Foundation
import SwiftData

@MainActor
func openConversationInAppState(
    conversationId: String,
    modelContext: ModelContext,
    appState: AppState
) {
    let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
        conversation.id == conversationId
    })

    guard let conversation = try? modelContext.fetch(descriptor).first,
          let thread = conversation.thread,
          thread.archivedAt == nil else {
        return
    }

    // Marking the conversation read is handled by ContentView's `.onChange(of: activeConversationId)`
    // observer, which fires on the SwiftUI pass after the selection mutation propagates.
    appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
    appState.selectedSidebarItem = .thread(thread)
}

@MainActor
func makeActiveConversationProvider(for appState: AppState) -> @MainActor () -> String? {
    { [weak appState] in
        guard let appState else {
            return nil
        }
        guard case .thread(let thread) = appState.selectedSidebarItem else {
            return nil
        }
        return appState.selectedConversation(in: thread)?.id
    }
}

extension ContentView {
    func openConversation(with conversationId: String) {
        openConversationInAppState(
            conversationId: conversationId,
            modelContext: uiModelContext,
            appState: appState
        )
    }

    func wireNotificationManager() {
        notificationManager.setActiveConversationProvider(makeActiveConversationProvider(for: appState))
    }
}
