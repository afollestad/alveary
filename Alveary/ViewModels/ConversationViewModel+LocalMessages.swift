import AgentCLIKit

extension ConversationViewModel {
    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        imageAttachments: [LocalImageAttachment] = [],
        appShots: [AppShotAttachment] = []
    ) -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: "message",
            role: "user",
            content: message,
            conversation: dbConversation
        )
        record.persistedImageAttachments = persistedTranscriptImageAttachments(
            imageAttachments: imageAttachments,
            appShots: appShots
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

        scheduleSave()
        return record
    }

    func previewTitle(for message: String, appShots: [AppShotAttachment]) -> String? {
        if !appShots.isEmpty {
            return Self.appShotThreadPreviewTitle(fromVisibleUserInput: message)
        }
        return AgentSessionPreviewGenerator.preview(fromInitialPrompt: message)
    }

    func persistedTranscriptImageAttachments(
        imageAttachments: [LocalImageAttachment],
        appShots: [AppShotAttachment]
    ) -> [LocalImageAttachment] {
        var attachments = imageAttachments
        var seenIDs = Set(attachments.map(\.id))
        for screenshot in appShots.map(\.screenshot) where seenIDs.insert(screenshot.id).inserted {
            attachments.append(screenshot)
        }
        return attachments
    }
}
