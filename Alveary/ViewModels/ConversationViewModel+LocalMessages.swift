import AgentCLIKit

extension ConversationViewModel {
    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        imageAttachments: [LocalImageAttachment] = [],
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        schedulesSave: Bool = true
    ) -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: "message",
            role: "user",
            content: message,
            conversation: dbConversation
        )
        record.setPersistedTranscriptAttachments(
            images: imageAttachments,
            appShots: appShots,
            files: fileAttachments
        )
        if !appShots.isEmpty {
            state.appShotProviderSessionTitleFallback = Self.appShotThreadPreviewTitle(fromVisibleUserInput: message)
        }
        modelContext.insert(record)
        state.grouper.appendLocalUserMessage(id: record.id, text: message)

        if !dbConversation.isMain,
           dbConversation.customTitle == nil,
           let name = previewTitle(for: message, appShots: appShots) {
            dbConversation.title = name
        }

        if schedulesSave {
            scheduleSave()
        }
        return record
    }

    func previewTitle(for message: String, appShots: [AppShotAttachment]) -> String? {
        if !appShots.isEmpty {
            return Self.appShotThreadPreviewTitle(fromVisibleUserInput: message)
        }
        return AgentSessionPreviewGenerator.preview(fromInitialPrompt: message)
    }

}
