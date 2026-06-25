import Foundation
import SwiftData

extension ConversationViewModel {
    var stagedImageAttachments: [LocalImageAttachment] {
        state.stagedImageAttachments
    }

    var stagedAppShots: [AppShotAttachment] {
        state.stagedAppShots
    }

    func stageAppShot(_ appShot: AppShotAttachment) {
        state.stagedAppShots.append(appShot)
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func removeStagedAppShot(id: String) {
        state.stagedAppShots.removeAll { $0.id == id }
        refreshInputDraftEffectiveEmptyForAttachments()
        cleanupUnreferencedImageAttachments(olderThan: 0)
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

    func clearStagedAppShots() {
        state.stagedAppShots.removeAll()
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
        guard let retainedURLs = retainedImageAttachmentURLs() else {
            return
        }
        let conversationID = conversation.id
        Task {
            await attachmentStore.cleanupUnreferenced(conversationId: conversationID, keeping: retainedURLs, olderThan: age)
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

    func clearStagedAppShotsIfTheyMatch(_ appShots: [AppShotAttachment]) {
        guard !appShots.isEmpty else {
            return
        }
        let ids = Set(appShots.map(\.id))
        state.stagedAppShots.removeAll { ids.contains($0.id) }
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func refreshInputDraftEffectiveEmptyForAttachments() {
        let textIsEffectivelyEmpty = ComposerDraft(
            text: state.inputDraft,
            source: state.inputDraftSource
        ).textIsEffectivelyEmpty
        state.inputDraftIsEffectivelyEmpty = textIsEffectivelyEmpty &&
            state.stagedImageAttachments.isEmpty &&
            state.stagedAppShots.isEmpty
    }
}

private extension ConversationViewModel {
    func retainedImageAttachmentURLs() -> Set<URL>? {
        var urls = Set(state.stagedImageAttachments.map { $0.fileURL.standardizedFileURL })
        urls.formUnion(state.stagedAppShots.map { $0.screenshot.fileURL.standardizedFileURL })
        for message in state.messageQueue.pending {
            urls.formUnion(message.attachments.map { $0.fileURL.standardizedFileURL })
            urls.formUnion(message.appShots.map { $0.screenshot.fileURL.standardizedFileURL })
        }
        for attachments in state.retryableFailedMessageAttachments.values {
            urls.formUnion(attachments.map { $0.fileURL.standardizedFileURL })
        }
        for appShots in state.retryableFailedMessageAppShots.values {
            urls.formUnion(appShots.map { $0.screenshot.fileURL.standardizedFileURL })
        }
        for attachments in state.transcriptImageAttachments.values {
            urls.formUnion(attachments.map { $0.fileURL.standardizedFileURL })
        }
        for appShots in state.transcriptAppShots.values {
            urls.formUnion(appShots.map { $0.screenshot.fileURL.standardizedFileURL })
        }
        guard let persistedURLs = persistedTranscriptImageAttachmentURLs() else {
            return nil
        }
        urls.formUnion(persistedURLs)
        return urls
    }

    func persistedTranscriptImageAttachmentURLs() -> Set<URL>? {
        let conversationID = conversation.id
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { $0.conversationId == conversationID }
        )
        guard let records = try? modelContext.fetch(descriptor) else {
            return nil
        }
        return Set(records.flatMap { record in
            record.persistedImageAttachments.map { $0.fileURL.standardizedFileURL }
        })
    }
}
