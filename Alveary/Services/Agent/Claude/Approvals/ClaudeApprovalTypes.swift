import Foundation

/// Stable key for a Claude approval interaction in a provider session.
struct ClaudeToolApprovalKey: Sendable, Hashable {
    let sessionId: String
    let toolUseId: String
}

/// User decision for a Claude tool approval prompt.
enum ClaudeToolApprovalDecision: String, Sendable, Equatable {
    case allow
    case deny
}

/// Complete approval resolution returned to `AgentCLIKit` for a live or deferred Claude tool prompt.
struct ClaudeToolApprovalResolution: Sendable, Equatable {
    let decision: ClaudeToolApprovalDecision
    let updatedInput: String?
    let responseText: String?

    /// Creates an approval resolution with optional updated input and host response text.
    init(decision: ClaudeToolApprovalDecision, updatedInput: String? = nil, responseText: String? = nil) {
        self.decision = decision
        self.updatedInput = updatedInput
        self.responseText = responseText
    }
}

/// Approval request published by the `AgentCLIKit` live hook bridge for Alveary UI handling.
struct ClaudeDeferredToolRequest: Sendable, Equatable {
    let conversationId: String
    let request: ToolApprovalRequest
}
