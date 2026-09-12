import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
    @Model
    final class ConversationEventRecord {
        static let messageType = "message"
        static let toolCallType = "tool_call"
        static let toolResultType = "tool_result"
        static let toolApprovalType = "tool_approval"
        static let tokensType = "tokens"
        static let errorType = "error"
        static let notificationEventType = "notification"
        static let stopType = "stop"
        static let sessionInitType = "session_init"
        static let contextWindowInvalidatedType = "context_window_invalidated"
        static let goalType = "goal"
        static let scheduledTaskNoteType = "scheduled_task_note"
        static let subAgentCompletedType = "sub_agent_completed"
        static let hostToolOutcomeType = "host_tool_outcome"
        static let taskListType = "task_list"
        static let steeredConversationType = "steered_conversation"
        static let userRole = "user"
        static let assistantRole = "assistant"
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
        var relayedFromConversationId: String?
        var relayedFromThreadName: String?
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

        init() {
            self.id = ""
            self.conversationId = ""
            self.type = ""
            self.role = nil
            self.content = nil
            self.transcriptAttachmentsJSON = nil
            self.toolId = nil
            self.toolName = nil
            self.toolInput = nil
            self.toolApprovalStatus = nil
            self.toolOutput = nil
            self.toolOutputStderr = nil
            self.toolOutputInterrupted = false
            self.toolOutputIsImage = false
            self.toolOutputNoOutputExpected = false
            self.parentToolUseId = nil
            self.callerAgent = nil
            self.relayedFromConversationId = nil
            self.relayedFromThreadName = nil
            self.isError = false
            self.tokenInput = 0
            self.tokenOutput = 0
            self.tokenCacheRead = 0
            self.tokenCacheCreation = 0
            self.durationMs = 0
            self.costUsd = 0
            self.costUsdReported = false
            self.providerModelId = nil
            self.contextWindowSize = nil
            self.notificationType = nil
            self.stopReason = nil
            self.timestamp = Date(timeIntervalSince1970: 0)
            self.conversation = nil
        }
    }
}
