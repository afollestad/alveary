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

    /// Creates a Claude approval resolution with an optional updated tool input payload.
    init(decision: ClaudeToolApprovalDecision, updatedInput: String? = nil) {
        self.decision = decision
        self.updatedInput = updatedInput
    }
}

/// Approval request published by the `AgentCLIKit` live hook bridge for Alveary UI handling.
struct ClaudeDeferredToolRequest: Sendable, Equatable {
    let conversationId: String
    let request: ToolApprovalRequest
}
