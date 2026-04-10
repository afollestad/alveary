import SwiftData

struct ToolResultMetadata: Sendable, Equatable {
    let stderr: String?
    let interrupted: Bool
    let isImage: Bool
    let noOutputExpected: Bool
}

struct PermissionDenialSummary: Sendable, Equatable {
    let toolName: String
    let toolUseId: String?
}

enum ConversationEvent: Sendable, Equatable {
    case sessionInit(sessionId: String?)
    case message(role: String, content: String, parentToolUseId: String?)
    case messageChunk(text: String, parentToolUseId: String?)
    case toolCall(id: String, name: String, input: String, parentToolUseId: String?, callerAgent: String?)
    case toolResult(id: String, output: String, isError: Bool, parentToolUseId: String?, metadata: ToolResultMetadata?)
    case thinking(content: String, parentToolUseId: String?)
    case tokens(
        input: Int,
        output: Int,
        cacheRead: Int,
        isError: Bool,
        stopReason: String?,
        durationMs: Int,
        costUsd: Double,
        permissionDenials: [PermissionDenialSummary]
    )
    case subAgentStarted(toolUseId: String, description: String, taskType: String?)
    case subAgentProgress(toolUseId: String, description: String?, lastToolName: String?, toolUses: Int, totalTokens: Int, durationMs: Int)
    case subAgentCompleted(toolUseId: String, status: String, toolUses: Int, totalTokens: Int, durationMs: Int)
    case notification(type: String, message: String?)
    case stop(message: String?)
    case error(message: String)

    @MainActor
    func toRecord(conversation: Conversation) -> ConversationEventRecord? {
        let record: ConversationEventRecord

        switch self {
        case .message(let role, let content, let parentToolUseId):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "message",
                role: role,
                content: content,
                conversation: conversation
            )
            record.parentToolUseId = parentToolUseId
        case .toolCall(let id, let name, let input, let parentToolUseId, let callerAgent):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "tool_call",
                toolId: id,
                toolName: name,
                toolInput: input,
                conversation: conversation
            )
            record.parentToolUseId = parentToolUseId
            record.callerAgent = callerAgent
        case .toolResult(let id, let output, let isError, let parentToolUseId, let metadata):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "tool_result",
                toolId: id,
                toolOutput: output,
                toolOutputStderr: metadata?.stderr,
                toolOutputInterrupted: metadata?.interrupted ?? false,
                toolOutputIsImage: metadata?.isImage ?? false,
                toolOutputNoOutputExpected: metadata?.noOutputExpected ?? false,
                isError: isError,
                conversation: conversation
            )
            record.parentToolUseId = parentToolUseId
        case .thinking(let content, let parentToolUseId):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "thinking",
                content: content,
                conversation: conversation
            )
            record.parentToolUseId = parentToolUseId
        case .tokens(let input, let output, let cacheRead, let isError, let stopReason, let durationMs, let costUsd, _):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "tokens",
                isError: isError,
                tokenInput: input,
                tokenOutput: output,
                tokenCacheRead: cacheRead,
                durationMs: durationMs,
                costUsd: costUsd,
                conversation: conversation
            )
            record.stopReason = stopReason
        case .notification(let type, let message):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "notification",
                content: message,
                notificationType: type,
                conversation: conversation
            )
        case .stop(let message):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "stop",
                content: message,
                conversation: conversation
            )
        case .sessionInit(let sessionId):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "session_init",
                content: sessionId,
                conversation: conversation
            )
        case .error(let message):
            record = ConversationEventRecord(
                conversationId: conversation.id,
                type: "error",
                content: message,
                conversation: conversation
            )
        case .messageChunk, .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            return nil
        }
        return record
    }
}
