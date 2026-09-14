import Foundation

struct AppKitTranscriptAttachments {
    var imagesByMessageID: [String: [TranscriptImageAttachment]] = [:]
    var filesByMessageID: [String: [LocalFileAttachment]] = [:]
}

/// Retains copied payloads and decoded values, never SwiftData records. Content edits can replace
/// attachment JSON without changing an event's id or the event count, including after a failed save.
@MainActor
final class AppKitTranscriptAttachmentCache {
    private var lastInputs: AppKitTranscriptAttachmentInputs?
    private var cachedAttachments = AppKitTranscriptAttachments()
    private var decodedByMessageID: [String: AppKitTranscriptAttachmentEnvelope] = [:]
    private(set) var decodeCount = 0
    private(set) var preparationCount = 0

    func attachments(
        events: [ConversationEventRecord],
        runtimeImageAttachments: [String: [LocalImageAttachment]],
        runtimeAppShots: [String: [AppShotAttachment]],
        runtimeFileAttachments: [String: [LocalFileAttachment]]
    ) -> AppKitTranscriptAttachments {
        let messages = events.filter { $0.type == ConversationEventRecord.messageType }
        let inputs = AppKitTranscriptAttachmentInputs(
            messages: messages.map {
                AppKitTranscriptAttachmentMessage(id: $0.id, role: $0.role, json: $0.transcriptAttachmentsJSON)
            },
            runtimeImages: runtimeImageAttachments,
            runtimeAppShots: runtimeAppShots,
            runtimeFiles: runtimeFileAttachments
        )
        if lastInputs == inputs {
            return cachedAttachments
        }

        var attachments = AppKitTranscriptAttachments()
        var liveEnvelopes: [String: AppKitTranscriptAttachmentEnvelope] = [:]
        for (message, event) in zip(inputs.messages, messages) {
            let envelope = decodedEnvelope(for: message, event: event)
            liveEnvelopes[message.id] = envelope
            ChatTranscriptView.appendTranscriptImageAttachments(
                envelope.attachments.images.map(TranscriptImageAttachment.init(localImageAttachment:)),
                to: message.id,
                in: &attachments.imagesByMessageID
            )
            ChatTranscriptView.appendTranscriptImageAttachments(
                envelope.attachments.appShots.map(TranscriptImageAttachment.init(appShot:)),
                to: message.id,
                in: &attachments.imagesByMessageID
            )
            if message.role == ConversationEventRecord.userRole {
                ChatTranscriptView.appendTranscriptFileAttachments(
                    envelope.attachments.files,
                    to: message.id,
                    in: &attachments.filesByMessageID
                )
            }
        }
        appendRuntimeAttachments(inputs, to: &attachments)
        decodedByMessageID = liveEnvelopes
        lastInputs = inputs
        cachedAttachments = attachments
        preparationCount += 1
        return attachments
    }

    private func decodedEnvelope(
        for message: AppKitTranscriptAttachmentMessage,
        event: ConversationEventRecord
    ) -> AppKitTranscriptAttachmentEnvelope {
        if let cached = decodedByMessageID[message.id], cached.json == message.json {
            return cached
        }
        if message.json != nil {
            decodeCount += 1
        }
        return AppKitTranscriptAttachmentEnvelope(json: message.json, attachments: event.persistedTranscriptAttachments)
    }

    private func appendRuntimeAttachments(
        _ inputs: AppKitTranscriptAttachmentInputs,
        to attachments: inout AppKitTranscriptAttachments
    ) {
        for (messageID, images) in inputs.runtimeImages {
            ChatTranscriptView.appendTranscriptImageAttachments(
                images.map(TranscriptImageAttachment.init(localImageAttachment:)),
                to: messageID,
                in: &attachments.imagesByMessageID
            )
        }
        for (messageID, appShots) in inputs.runtimeAppShots {
            ChatTranscriptView.appendTranscriptImageAttachments(
                appShots.map(PersistedAppShotAttachment.init(appShot:)).map(TranscriptImageAttachment.init(appShot:)),
                to: messageID,
                in: &attachments.imagesByMessageID
            )
        }
        for (messageID, files) in inputs.runtimeFiles {
            ChatTranscriptView.appendTranscriptFileAttachments(files, to: messageID, in: &attachments.filesByMessageID)
        }
    }
}

private struct AppKitTranscriptAttachmentInputs: Equatable {
    let messages: [AppKitTranscriptAttachmentMessage]
    let runtimeImages: [String: [LocalImageAttachment]]
    let runtimeAppShots: [String: [AppShotAttachment]]
    let runtimeFiles: [String: [LocalFileAttachment]]
}

private struct AppKitTranscriptAttachmentMessage: Equatable {
    let id: String
    let role: String?
    let json: String?
}

private struct AppKitTranscriptAttachmentEnvelope {
    let json: String?
    let attachments: PersistedTranscriptAttachments
}
