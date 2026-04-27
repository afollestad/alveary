import Foundation
import SwiftData

@Model
final class ConversationEventRecord {
    static let contextWindowInvalidatedType = "context_window_invalidated"

    #Index<ConversationEventRecord>([\.conversationId, \.timestamp])

    @Attribute(.unique) var id: String
    var conversationId: String
    var type: String
    var role: String?
    var content: String?
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
        self.providerModelId = providerModelId
        self.contextWindowSize = contextWindowSize
        self.notificationType = notificationType
        self.stopReason = stopReason
        self.timestamp = timestamp
        self.conversation = conversation
    }
}
