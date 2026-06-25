import Foundation

extension ConversationViewModel {
    var stagedImageAttachments: [LocalImageAttachment] {
        state.stagedImageAttachments
    }

    func stageLocalImageAttachments(from urls: [URL]) async throws {
        let imageURLs = urls.filter(DefaultConversationAttachmentStore.isSupportedImageURL(_:))
        guard !imageURLs.isEmpty else {
            return
        }
        let attachments = try await attachmentStore.copyLocalImages(imageURLs, conversationId: conversation.id)
        state.stagedImageAttachments.append(contentsOf: attachments)
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func removeStagedImageAttachment(id: String) {
        state.stagedImageAttachments.removeAll { $0.id == id }
        refreshInputDraftEffectiveEmptyForAttachments()
        cleanupUnreferencedImageAttachments(olderThan: 0)
    }

    func clearStagedImageAttachments() {
        state.stagedImageAttachments.removeAll()
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func fallbackText(
        visibleText: String,
        attachments: [LocalImageAttachment]
    ) -> String {
        guard !attachments.isEmpty else {
            return visibleText
        }
        let attachmentMarkdown = attachments.map(\.markdownImageLink).joined(separator: "\n")
        guard !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return attachmentMarkdown
        }
        return visibleText + "\n\n" + attachmentMarkdown
    }

    func cleanupUnreferencedImageAttachments(olderThan age: TimeInterval = 60 * 60 * 24 * 30) {
        let retainedURLs = retainedImageAttachmentURLs()
        Task {
            await attachmentStore.cleanupUnreferenced(keeping: retainedURLs, olderThan: age)
        }
    }

    func clearStagedImageAttachmentsIfTheyMatch(_ attachments: [LocalImageAttachment]) {
        guard !attachments.isEmpty else {
            return
        }
        let attachmentIDs = Set(attachments.map(\.id))
        state.stagedImageAttachments.removeAll { attachmentIDs.contains($0.id) }
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func refreshInputDraftEffectiveEmptyForAttachments() {
        let textIsEffectivelyEmpty = ComposerDraft(
            text: state.inputDraft,
            source: state.inputDraftSource
        ).textIsEffectivelyEmpty
        state.inputDraftIsEffectivelyEmpty = textIsEffectivelyEmpty && state.stagedImageAttachments.isEmpty
    }
}

private extension ConversationViewModel {
    func retainedImageAttachmentURLs() -> Set<URL> {
        var urls = Set(state.stagedImageAttachments.map { $0.fileURL.standardizedFileURL })
        for message in state.messageQueue.pending {
            urls.formUnion(message.attachments.map { $0.fileURL.standardizedFileURL })
        }
        for attachments in state.retryableFailedMessageAttachments.values {
            urls.formUnion(attachments.map { $0.fileURL.standardizedFileURL })
        }
        for attachments in state.transcriptImageAttachments.values {
            urls.formUnion(attachments.map { $0.fileURL.standardizedFileURL })
        }
        return urls
    }
}
