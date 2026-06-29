import Foundation
import SwiftData

@Model
final class ConversationEventRecord {
    static let contextWindowInvalidatedType = "context_window_invalidated"
    static let goalType = "goal"
    static let subAgentCompletedType = "sub_agent_completed"
    static let taskListType = "task_list"
    static let steeredConversationType = "steered_conversation"

    #Index<ConversationEventRecord>([\.conversationId, \.timestamp])

    @Attribute(.unique) var id: String
    var conversationId: String
    var type: String
    var role: String?
    var content: String?
    var transcriptAttachmentsJSON: String?
    var toolId: String?
    var toolName: String?
    var toolInput: String?
    var toolApprovalStatus: String?
    var toolOutput: String?
    var toolOutputStderr: String?
    var toolOutputInterrupted: Bool
    var toolOutputIsImage: Bool
    var toolOutputNoOutputExpected: Bool
    var parentToolUseId: String?
    var callerAgent: String?
    var isError: Bool
    var tokenInput: Int
    var tokenOutput: Int
    var tokenCacheRead: Int
    var tokenCacheCreation: Int = 0
    var durationMs: Int
    var costUsd: Double
    var costUsdReported: Bool = false
    var providerModelId: String?
    var contextWindowSize: Int?
    var notificationType: String?
    var stopReason: String?
    var timestamp: Date
    var conversation: Conversation?

    init(
        id: String = UUID().uuidString,
        conversationId: String? = nil,
        type: String,
        role: String? = nil,
        content: String? = nil,
        transcriptAttachmentsJSON: String? = nil,
        toolId: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolApprovalStatus: String? = nil,
        toolOutput: String? = nil,
        toolOutputStderr: String? = nil,
        toolOutputInterrupted: Bool = false,
        toolOutputIsImage: Bool = false,
        toolOutputNoOutputExpected: Bool = false,
        parentToolUseId: String? = nil,
        callerAgent: String? = nil,
        isError: Bool = false,
        tokenInput: Int = 0,
        tokenOutput: Int = 0,
        tokenCacheRead: Int = 0,
        tokenCacheCreation: Int = 0,
        durationMs: Int = 0,
        costUsd: Double = 0,
        costUsdReported: Bool = false,
        providerModelId: String? = nil,
        contextWindowSize: Int? = nil,
        notificationType: String? = nil,
        stopReason: String? = nil,
        timestamp: Date = .now,
        conversation: Conversation? = nil
    ) {
        guard let resolvedConversationId = conversationId ?? conversation?.id else {
            preconditionFailure("ConversationEventRecord requires either `conversationId` or `conversation`")
        }
        if let conversation, conversation.id != resolvedConversationId {
            preconditionFailure("`conversationId` must match `conversation.id`")
        }

        self.id = id
        self.conversationId = resolvedConversationId
        self.type = type
        self.role = role
        self.content = content
        self.transcriptAttachmentsJSON = transcriptAttachmentsJSON
        self.toolId = toolId
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolApprovalStatus = toolApprovalStatus
        self.toolOutput = toolOutput
        self.toolOutputStderr = toolOutputStderr
        self.toolOutputInterrupted = toolOutputInterrupted
        self.toolOutputIsImage = toolOutputIsImage
        self.toolOutputNoOutputExpected = toolOutputNoOutputExpected
        self.parentToolUseId = parentToolUseId
        self.callerAgent = callerAgent
        self.isError = isError
        self.tokenInput = tokenInput
        self.tokenOutput = tokenOutput
        self.tokenCacheRead = tokenCacheRead
        self.tokenCacheCreation = tokenCacheCreation
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.costUsdReported = costUsdReported
        self.providerModelId = providerModelId
        self.contextWindowSize = contextWindowSize
        self.notificationType = notificationType
        self.stopReason = stopReason
        self.timestamp = timestamp
        self.conversation = conversation
    }
}

extension ConversationEventRecord {
    var persistedTranscriptAttachments: PersistedTranscriptAttachments {
        guard let transcriptAttachmentsJSON,
              let data = transcriptAttachmentsJSON.data(using: .utf8) else {
            return .empty
        }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(PersistedTranscriptAttachmentsEnvelope.self, from: data) {
            return PersistedTranscriptAttachments(
                images: envelope.images,
                appShots: envelope.appShots,
                files: envelope.files
            )
        }
        if let legacyImages = try? decoder.decode([LocalImageAttachment].self, from: data) {
            return PersistedTranscriptAttachments(images: legacyImages, appShots: [], files: [])
        }
        return .empty
    }

    var persistedPlainImageAttachments: [LocalImageAttachment] {
        persistedTranscriptAttachments.images
    }

    var persistedAppShotAttachments: [PersistedAppShotAttachment] {
        persistedTranscriptAttachments.appShots
    }

    var persistedFileAttachments: [LocalFileAttachment] {
        persistedTranscriptAttachments.files
    }

    var persistedImageAttachments: [LocalImageAttachment] {
        persistedTranscriptAttachments.combinedImageAttachments
    }

    func setPersistedPlainImageAttachments(_ attachments: [LocalImageAttachment]) {
        setPersistedTranscriptAttachments(images: attachments, persistedAppShots: [], files: [])
    }

    func setPersistedTranscriptAttachments(
        images: [LocalImageAttachment],
        appShots: [AppShotAttachment],
        files: [LocalFileAttachment] = []
    ) {
        setPersistedTranscriptAttachments(
            images: images,
            persistedAppShots: appShots.map(PersistedAppShotAttachment.init(appShot:)),
            files: files
        )
    }

    func setPersistedTranscriptAttachments(
        images: [LocalImageAttachment],
        persistedAppShots: [PersistedAppShotAttachment],
        files: [LocalFileAttachment] = []
    ) {
        let transcriptAttachments = PersistedTranscriptAttachments(
            images: images,
            appShots: persistedAppShots,
            files: files
        )
        guard !transcriptAttachments.isEmpty else {
            transcriptAttachmentsJSON = nil
            return
        }
        let envelope = PersistedTranscriptAttachmentsEnvelope(
            version: PersistedTranscriptAttachmentsEnvelope.currentVersion,
            images: transcriptAttachments.images,
            appShots: transcriptAttachments.appShots,
            files: transcriptAttachments.files
        )
        guard let data = try? JSONEncoder().encode(envelope) else {
            transcriptAttachmentsJSON = nil
            return
        }
        transcriptAttachmentsJSON = String(data: data, encoding: .utf8)
    }

    var isHiddenGoalRecord: Bool {
        type == Self.goalType
    }

    var isVisibleTranscriptEvent: Bool {
        switch type {
        case Self.contextWindowInvalidatedType,
             Self.goalType,
             Self.subAgentCompletedType,
             "session_init":
            return false
        default:
            return true
        }
    }
}

struct PersistedTranscriptAttachments: Equatable {
    static let empty = PersistedTranscriptAttachments(images: [], appShots: [], files: [])

    let images: [LocalImageAttachment]
    let appShots: [PersistedAppShotAttachment]
    let files: [LocalFileAttachment]

    var isEmpty: Bool {
        images.isEmpty && appShots.isEmpty && files.isEmpty
    }

    var combinedImageAttachments: [LocalImageAttachment] {
        var combined = images
        var seenIDs = Set(images.map(\.id))
        for appShot in appShots where seenIDs.insert(appShot.screenshot.id).inserted {
            combined.append(appShot.screenshot)
        }
        return combined
    }
}

private struct PersistedTranscriptAttachmentsEnvelope: Codable {
    static let currentVersion = 2

    let version: Int
    let images: [LocalImageAttachment]
    let appShots: [PersistedAppShotAttachment]
    let files: [LocalFileAttachment]

    init(
        version: Int,
        images: [LocalImageAttachment],
        appShots: [PersistedAppShotAttachment],
        files: [LocalFileAttachment]
    ) {
        self.version = version
        self.images = images
        self.appShots = appShots
        self.files = files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        images = try container.decode([LocalImageAttachment].self, forKey: .images)
        appShots = try container.decode([PersistedAppShotAttachment].self, forKey: .appShots)
        files = try container.decodeIfPresent([LocalFileAttachment].self, forKey: .files) ?? []
    }
}
