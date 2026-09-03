import AgentCLIKit

extension ConversationViewModel {
    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        imageAttachments: [LocalImageAttachment] = [],
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        relayedFrom: RelayedPromptAttribution? = nil,
        schedulesSave: Bool = true
    ) -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: ConversationEventRecord.messageType,
            role: ConversationEventRecord.userRole,
            content: message,
            relayedFromConversationId: relayedFrom?.conversationID,
            relayedFromThreadName: relayedFrom?.threadName,
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
        state.grouper.appendLocalUserMessage(id: record.id, text: message, relayedFromThreadName: relayedFrom?.threadName)
        scanInsertedMessageRecordForPullRequestLinks(record)

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

    /// The drain and the steer both record a queued message the same way; one helper keeps the
    /// two argument lists from drifting apart.
    @discardableResult
    func insertLocalUserMessage(
        for queuedMessage: QueuedMessage,
        into dbConversation: Conversation
    ) -> ConversationEventRecord {
        insertLocalUserMessage(
            queuedMessage.text,
            into: dbConversation,
            imageAttachments: queuedMessage.attachments,
            fileAttachments: queuedMessage.fileAttachments,
            appShots: queuedMessage.appShots,
            relayedFrom: queuedMessage.relayedFrom
        )
    }

    func previewTitle(for message: String, appShots: [AppShotAttachment]) -> String? {
        if !appShots.isEmpty {
            return Self.appShotThreadPreviewTitle(fromVisibleUserInput: message)
        }
        return AgentSessionPreviewGenerator.preview(fromInitialPrompt: message)
    }

}
