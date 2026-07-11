import Foundation
import SwiftData

struct RestoredThreadSelection {
    let thread: AgentThread
    let conversationID: PersistentIdentifier
}

func resolvedLastOpenThreadSelection(
    settings: AppSettings,
    modelContext: ModelContext
) -> RestoredThreadSelection? {
    guard settings.reopenLastThreadAndConversationOnLaunch,
          let threadID = settings.lastOpenThreadID,
          let conversationID = settings.lastOpenConversationID else {
        return nil
    }

    let threadDescriptor = FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
        thread.persistentModelID == threadID && thread.archivedAt == nil && thread.isDraft == false
    })

    let conversationDescriptor = FetchDescriptor<Conversation>(predicate: #Predicate { conversation in
        conversation.persistentModelID == conversationID && conversation.thread?.persistentModelID == threadID
    })

    guard let threads = try? modelContext.fetch(threadDescriptor),
          let thread = threads.first,
          (try? modelContext.fetch(conversationDescriptor).first) != nil else {
        return nil
    }

    return RestoredThreadSelection(thread: thread, conversationID: conversationID)
}

extension ContentView {
    func restoreLastOpenThreadSelectionIfNeeded() {
        guard !didAttemptLaunchSelectionRestore else {
            return
        }
        didAttemptLaunchSelectionRestore = true

        let settings = settingsService.current

        guard appState.selectedSidebarItem == nil,
              let selection = resolvedLastOpenThreadSelection(
                  settings: settings,
                  modelContext: uiModelContext
              ) else {
            clearLastOpenThreadSelectionIfNeeded(settings: settings)
            return
        }

        appState.selectedConversationIDs[selection.thread.persistentModelID] = selection.conversationID
        appState.selectedSidebarItem = .thread(selection.thread)
    }

    func clearLastOpenThreadSelectionIfNeeded(settings: AppSettings) {
        guard settings.reopenLastThreadAndConversationOnLaunch,
              settings.lastOpenThreadID != nil || settings.lastOpenConversationID != nil else {
            return
        }

        settingsService.updateRestoreSelection(threadID: nil, conversationID: nil)
    }
}
