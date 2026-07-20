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
          thread.archivedAt == nil,
          !thread.isDraft else {
        return
    }

    // Marking the conversation read is handled by `ThreadDetailView` after
    // the selected conversation mounts.
    appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
    appState.selectedSidebarItem = .thread(thread)
}

@MainActor
func selectedConversation(
    in thread: AgentThread,
    modelContext: ModelContext,
    appState: AppState
) -> Conversation? {
    let threadID = thread.persistentModelID
    let descriptor = FetchDescriptor<Conversation>(
        predicate: #Predicate { conversation in
            conversation.thread?.persistentModelID == threadID
        }
    )
    let conversations = (try? modelContext.fetch(descriptor)) ?? []
    return appState.selectedConversation(in: thread, conversations: conversations)
}

@MainActor
func makeActiveConversationProvider(for appState: AppState, modelContext: ModelContext) -> @MainActor () -> String? {
    { [weak appState, modelContext] in
        guard let appState else {
            return nil
        }
        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              let thread = modelContext.resolveThread(id: selectedThread.persistentModelID) else {
            return nil
        }
        guard !thread.isDraft else {
            return nil
        }
        return selectedConversation(in: thread, modelContext: modelContext, appState: appState)?.id
    }
}

extension ContentView {
    func replayModelPreparationDeferredRoutingIfAvailable() {
        guard !voiceInputLifecycleController.isModelPreparationModalPresented else {
            return
        }
        handlePendingCommand(appState.pendingCommand)
        routePendingConversationIfModelPreparationAllows(notificationRouter.pendingConversationId)
        routePendingScheduledTaskIfModelPreparationAllows(notificationRouter.pendingScheduledTaskDefinitionId)
    }

    func routePendingConversationIfModelPreparationAllows(_ conversationID: String?) {
        guard let conversationID else {
            return
        }
        performAppNavigationIfModelPreparationModalAbsent(
            lifecycleController: voiceInputLifecycleController
        ) {
            openConversation(with: conversationID)
            notificationRouter.clearPendingIfMatches(conversationID)
        }
    }

    func routePendingScheduledTaskIfModelPreparationAllows(_ definitionID: String?) {
        guard let definitionID else {
            return
        }
        performAppNavigationIfModelPreparationModalAbsent(
            lifecycleController: voiceInputLifecycleController
        ) {
            openScheduledTaskDefinition(with: definitionID)
            notificationRouter.clearPendingScheduledTaskIfMatches(definitionID)
        }
    }

    func openScheduledTaskDefinition(with definitionID: String) {
        openScheduledTaskDefinitionInAppState(
            definitionID: definitionID,
            appState: appState,
            viewModel: scheduledTasksViewModel
        )
    }

    func openConversation(with conversationId: String) {
        openConversationInAppState(
            conversationId: conversationId,
            modelContext: uiModelContext,
            appState: appState
        )
    }

    func wireNotificationManager() {
        notificationManager.setActiveConversationProvider(makeActiveConversationProvider(for: appState, modelContext: uiModelContext))
    }
}

@MainActor
func openScheduledTaskDefinitionInAppState(
    definitionID: String,
    appState: AppState,
    viewModel: ScheduledTasksViewModel
) {
    appState.selectedSidebarItem = .scheduled
    viewModel.requestEdit(definitionID: definitionID)
}
