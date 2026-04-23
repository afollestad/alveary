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
        thread.persistentModelID == threadID && thread.archivedAt == nil
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

    func persistLastOpenThreadSelection(for item: SidebarItem?) {
        guard case .thread(let selectedThread) = item,
              let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID),
              thread.archivedAt == nil else {
            return
        }

        settingsService.update {
            $0.lastOpenThreadID = thread.persistentModelID
            $0.lastOpenConversationID = selectedConversation(
                in: thread,
                modelContext: uiModelContext,
                appState: appState
            )?.persistentModelID
        }
    }

    func clearLastOpenThreadSelectionIfNeeded(settings: AppSettings) {
        guard settings.reopenLastThreadAndConversationOnLaunch,
              settings.lastOpenThreadID != nil || settings.lastOpenConversationID != nil else {
            return
        }

        settingsService.update {
            $0.lastOpenThreadID = nil
            $0.lastOpenConversationID = nil
        }
    }
}
