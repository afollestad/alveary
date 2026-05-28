import AgentCLIKit
import Foundation

actor AgentCLIKitClaudeApprovalStoreAdapter: AgentCLIKit.ClaudeApprovalPolicyStoring, AgentCLIKit.ClaudeTransientDecisionStoring {
    private let claudeHookServer: any ClaudeHookServer
    private let fallbackStore = AgentCLIKit.ClaudeApprovalPolicyStore()

    init(claudeHookServer: any ClaudeHookServer) {
        self.claudeHookServer = claudeHookServer
    }

    func approveForSession(operation: String) async {
        await fallbackStore.approveForSession(operation: operation)
    }

    func approveForSession(operation: String, input: AgentCLIKit.JSONValue) async {
        await fallbackStore.approveForSession(operation: operation, input: input)
    }

    func isSessionApproved(operation: String) async -> Bool {
        await fallbackStore.isSessionApproved(operation: operation)
    }

    func isSessionApproved(operation: String, input: AgentCLIKit.JSONValue) async -> Bool {
        await fallbackStore.isSessionApproved(operation: operation, input: input)
    }

    func recordSessionApproval(_ grant: AgentCLIKit.AgentSessionApprovalGrant) async -> AgentCLIKit.AgentSessionApprovalRecordResult {
        guard let approval = alvearySessionApproval(grant) else {
            return AgentCLIKit.AgentSessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }
        let result = await claudeHookServer.recordSessionApproval(approval)
        return AgentCLIKit.AgentSessionApprovalRecordResult(
            isEffective: result.isEffective,
            wasInserted: result.wasInserted
        )
    }

    func discardSessionApproval(_ grant: AgentCLIKit.AgentSessionApprovalGrant) async {
        guard let approval = alvearySessionApproval(grant) else {
            return
        }
        await claudeHookServer.discardSessionApproval(approval)
    }

    func allowsSessionApproval(_ request: AgentCLIKit.AgentSessionApprovalRequest) async -> Bool {
        await claudeHookServer.allowsSessionApproval(
            providerId: request.providerId.rawValue,
            conversationId: request.conversationId.rawValue,
            sessionId: request.sessionId.rawValue,
            toolName: request.toolName,
            toolInput: Self.serialized(request.toolInput)
        )
    }

    func removeSessionApprovals(
        providerId: AgentCLIKit.AgentProviderID,
        conversationId: AgentCLIKit.AgentConversationID,
        sessionId: AgentCLIKit.AgentSessionID
    ) async {
        await claudeHookServer.removeSessionApprovals(
            conversationId: conversationId.rawValue,
            sessionId: sessionId.rawValue
        )
    }

    func approveBatch(_ ids: [AgentCLIKit.AgentInteractionID]) async {
        await fallbackStore.approveBatch(ids)
    }

    func consumeTransientApproval(id: AgentCLIKit.AgentInteractionID) async -> Bool {
        await fallbackStore.consumeTransientApproval(id: id)
    }

    func recordTransientDecision(
        _ decision: AgentCLIKit.ClaudeHookDecision,
        id: AgentCLIKit.AgentInteractionID
    ) async {
        await fallbackStore.recordTransientDecision(decision, id: id)
    }

    func consumeTransientDecision(id: AgentCLIKit.AgentInteractionID) async -> AgentCLIKit.ClaudeHookDecision? {
        await fallbackStore.consumeTransientDecision(id: id)
    }

    func discardTransientDecision(id: AgentCLIKit.AgentInteractionID) async {
        await fallbackStore.discardTransientDecision(id: id)
    }

    func recordTransientDecision(
        _ decision: AgentCLIKit.ClaudeHookDecision,
        for key: AgentCLIKit.ClaudeTransientDecisionKey
    ) async {
        await fallbackStore.recordTransientDecision(decision, for: key)
    }

    func consumeTransientDecision(
        for key: AgentCLIKit.ClaudeTransientDecisionKey
    ) async -> AgentCLIKit.ClaudeHookDecision? {
        await fallbackStore.consumeTransientDecision(for: key)
    }

    func discardTransientDecision(for key: AgentCLIKit.ClaudeTransientDecisionKey) async {
        await fallbackStore.discardTransientDecision(for: key)
    }

    private func alvearySessionApproval(_ grant: AgentCLIKit.AgentSessionApprovalGrant) -> AgentSessionApprovalGrant? {
        guard let matchKind = AgentSessionApprovalRuleKind(rawValue: grant.matchKind.rawValue) else {
            return nil
        }
        return AgentSessionApprovalGrant(
            providerId: grant.providerId.rawValue,
            conversationId: grant.conversationId.rawValue,
            sessionId: grant.sessionId.rawValue,
            matchKind: matchKind,
            matchValue: grant.matchValue
        )
    }

    private static func serialized(_ value: AgentCLIKit.JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
