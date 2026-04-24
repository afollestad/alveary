import Foundation
import SwiftData

enum ConversationInterruption {
    static let requestInterruptedByUserMarker = "[Request interrupted by user]"
    static let requestInterruptedByUserForToolUseMarker = "[Request interrupted by user for tool use]"
    static let requestInterruptedByUserReason = "Request interrupted by user"
    static let displayMessage = "Interrupted"

    static func isRequestInterruptedByUserMarker(_ text: String) -> Bool {
        isRequestInterruptedByUserText(text)
    }

    static func isRequestInterruptedByUserReason(_ text: String?) -> Bool {
        guard let text else {
            return false
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedText.caseInsensitiveCompare(requestInterruptedByUserReason) == .orderedSame ||
            isRequestInterruptedByUserText(normalizedText)
    }

    static func isDisplayMessage(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) == displayMessage
    }

    private static func isRequestInterruptedByUserText(_ text: String) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            requestInterruptedByUserMarker,
            requestInterruptedByUserForToolUseMarker
        ].contains { normalizedText.caseInsensitiveCompare($0) == .orderedSame }
    }
}

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

struct ToolApprovalFailure: Sendable, Equatable {
    let sessionId: String?
    let toolUseId: String?
    let toolName: String?
    let message: String
}

enum ConversationEvent: Sendable, Equatable {
    case sessionInit(sessionId: String?)
    case permissionModeChanged(String)
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
    case toolApprovalRequested(ToolApprovalRequest)
    case toolApprovalFailed(ToolApprovalFailure)
    case subAgentStarted(toolUseId: String, description: String, taskType: String?)
    case subAgentProgress(toolUseId: String, description: String?, lastToolName: String?, toolUses: Int, totalTokens: Int, durationMs: Int)
    case subAgentCompleted(toolUseId: String, status: String, toolUses: Int, totalTokens: Int, durationMs: Int)
    case notification(type: String, message: String?)
    case stop(message: String?)
    case error(message: String)

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    func toRecord(conversation: Conversation) -> ConversationEventRecord? {
        switch self {
        case .message:
            return messageRecord(conversation: conversation)
        case .toolCall:
            return toolCallRecord(conversation: conversation)
        case .toolResult:
            return toolResultRecord(conversation: conversation)
        case .thinking:
            return thinkingRecord(conversation: conversation)
        case .tokens:
            return tokensRecord(conversation: conversation)
        case .toolApprovalRequested:
            return toolApprovalRecord(conversation: conversation)
        case .toolApprovalFailed:
            return toolApprovalFailureRecord(conversation: conversation)
        case .notification:
            return notificationRecord(conversation: conversation)
        case .stop:
            return stopRecord(conversation: conversation)
        case .sessionInit:
            return sessionInitRecord(conversation: conversation)
        case .error:
            return errorRecord(conversation: conversation)
        case .messageChunk, .subAgentStarted, .subAgentProgress, .subAgentCompleted, .permissionModeChanged:
            return nil
        }
    }
}

private extension ConversationEvent {
    @MainActor
    func messageRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .message(role, content, parentToolUseId) = self else {
            preconditionFailure("Unexpected event case")
        }

        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: role,
            content: content,
            conversation: conversation
        )
        record.parentToolUseId = parentToolUseId
        return record
    }

    @MainActor
    func toolCallRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .toolCall(id, name, input, parentToolUseId, callerAgent) = self else {
            preconditionFailure("Unexpected event case")
        }

        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: id,
            toolName: name,
            toolInput: input,
            conversation: conversation
        )
        record.parentToolUseId = parentToolUseId
        record.callerAgent = callerAgent
        return record
    }

    @MainActor
    func toolResultRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .toolResult(id, output, isError, parentToolUseId, metadata) = self else {
            preconditionFailure("Unexpected event case")
        }

        let record = ConversationEventRecord(
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
        return record
    }

    @MainActor
    func thinkingRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .thinking(content, parentToolUseId) = self else {
            preconditionFailure("Unexpected event case")
        }

        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: "thinking",
            content: content,
            conversation: conversation
        )
        record.parentToolUseId = parentToolUseId
        return record
    }

    @MainActor
    func tokensRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .tokens(input, output, cacheRead, isError, stopReason, durationMs, costUsd, _) = self else {
            preconditionFailure("Unexpected event case")
        }

        let record = ConversationEventRecord(
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
        return record
    }

    @MainActor
    func toolApprovalRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .toolApprovalRequested(request) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: request.sessionId,
            toolId: request.toolUseId,
            toolName: request.toolName,
            toolInput: request.toolInput,
            conversation: conversation
        )
    }

    @MainActor
    func toolApprovalFailureRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .toolApprovalFailed(failure) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "error",
            content: failure.message,
            toolId: failure.toolUseId,
            toolName: failure.toolName,
            conversation: conversation
        )
    }

    @MainActor
    func notificationRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .notification(type, message) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "notification",
            content: message,
            notificationType: type,
            conversation: conversation
        )
    }

    @MainActor
    func stopRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .stop(message) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "stop",
            content: message,
            conversation: conversation
        )
    }

    @MainActor
    func sessionInitRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .sessionInit(sessionId) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "session_init",
            content: sessionId,
            conversation: conversation
        )
    }

    @MainActor
    func errorRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .error(message) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: "error",
            content: message,
            conversation: conversation
        )
    }
}
