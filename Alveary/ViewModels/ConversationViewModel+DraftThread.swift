import Foundation

extension ConversationViewModel {
    func flushPendingChangesBeforeDraftSave() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }

    func materializeDraftWithoutMessageIfNeeded() throws {
        guard let conversation = dbConversation(),
              let thread = conversation.thread,
              thread.isDraft else {
            return
        }

        try flushPendingChangesBeforeDraftSave()
        thread.isDraft = false
        do {
            try draftMaterializationSaver()
        } catch {
            thread.isDraft = true // Restore the identity-map value before SwiftData discards the failed transaction.
            modelContext.rollback()
            throw error
        }
        publishDraftMaterialized(thread: thread, conversation: conversation)
    }

    func publishDraftMaterialized(thread: AgentThread, conversation: Conversation) {
        let threadID = thread.persistentModelID
        let conversationID = conversation.persistentModelID
        let projectPath = thread.project?.path
        settingsService.updateRestoreSelection(threadID: threadID, conversationID: conversationID)

        var userInfo: [String: Any] = [
            ThreadDraftNotificationKey.threadID: threadID,
            ThreadDraftNotificationKey.conversationID: conversationID
        ]
        if let projectPath {
            userInfo[ThreadDraftNotificationKey.projectPath] = projectPath
        }
        NotificationCenter.default.post(name: .threadDraftMaterialized, object: nil, userInfo: userInfo)
    }
}
