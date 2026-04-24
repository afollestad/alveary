import Foundation

struct ClaudeHookLaunchConfig: Sendable, Equatable {
    let arguments: [String]
    let environment: [String: String]
}

struct ClaudeToolApprovalKey: Sendable, Hashable {
    let sessionId: String
    let toolUseId: String
}

enum ClaudeToolApprovalDecision: String, Sendable, Equatable {
    case allow
    case deny
}

struct ClaudeToolApprovalResolution: Sendable, Equatable {
    let decision: ClaudeToolApprovalDecision
    let updatedInput: String?

    init(decision: ClaudeToolApprovalDecision, updatedInput: String? = nil) {
        self.decision = decision
        self.updatedInput = updatedInput
    }
}

struct ClaudeDeferredToolRequest: Sendable, Equatable {
    let conversationId: String
    let launchToken: String?
    let request: ToolApprovalRequest
}
