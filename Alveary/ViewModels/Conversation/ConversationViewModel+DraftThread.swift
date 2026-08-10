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
        try commitDraftMaterialization(thread)
        publishDraftMaterialized(thread: thread, conversation: conversation)
    }

    func commitDraftMaterialization(_ thread: AgentThread) throws {
        let previousModifiedAt = thread.modifiedAt
        thread.isDraft = false
        if thread.mode == .task {
            thread.modifiedAt = Date.now
        }
        do {
            try draftMaterializationSaver()
        } catch {
            thread.isDraft = true // Restore the identity-map value before SwiftData discards the failed transaction.
            thread.modifiedAt = previousModifiedAt
            modelContext.rollback()
            throw error
        }
    }

    func publishDraftMaterialized(thread: AgentThread, conversation: Conversation) {
        let threadID = thread.persistentModelID
        let conversationID = conversation.persistentModelID
        let projectPath = thread.project?.path
        settingsService.updateRestoreSelection(threadID: threadID, conversationID: conversationID)
        if thread.mode == .task {
            threadActivityRecorder.recordTaskMaterialized(conversationId: conversation.id)
        }

        var userInfo: [String: Any] = [
            ThreadDraftNotificationKey.threadID: threadID,
            ThreadDraftNotificationKey.conversationID: conversationID,
            ThreadDraftNotificationKey.mode: thread.mode.rawValue
        ]
        if let projectPath {
            userInfo[ThreadDraftNotificationKey.projectPath] = projectPath
        }
        NotificationCenter.default.post(name: .threadDraftMaterialized, object: nil, userInfo: userInfo)
    }
}
