import AgentCLIKit
import Foundation

/// Bridges `AgentCLIKit` Claude approval policy storage to Alveary's durable approval store.
///
/// Session-scoped reusable approvals are persisted by Alveary so the UI can preserve
/// approval selections across app launches. Transient one-shot and batch fallback
/// decisions remain in `AgentCLIKit.ClaudeApprovalPolicyStore` because they belong to
/// the provider hook runtime.
actor AgentCLIKitClaudeApprovalStoreAdapter: AgentCLIKit.ClaudeApprovalPolicyStoring, AgentCLIKit.ClaudeTransientDecisionStoring {
    private let approvalPersistenceStore: any ClaudeApprovalPersistenceStore
    private let fallbackStore = AgentCLIKit.ClaudeApprovalPolicyStore()

    /// Creates an adapter backed by Alveary's approval persistence store.
    init(approvalPersistenceStore: any ClaudeApprovalPersistenceStore) {
        self.approvalPersistenceStore = approvalPersistenceStore
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
        let result = await approvalPersistenceStore.recordSessionApproval(approval)
        return AgentCLIKit.AgentSessionApprovalRecordResult(
            isEffective: result.isEffective,
            wasInserted: result.wasInserted
        )
    }

    func discardSessionApproval(_ grant: AgentCLIKit.AgentSessionApprovalGrant) async {
        guard let approval = alvearySessionApproval(grant) else {
            return
        }
        await approvalPersistenceStore.discardSessionApproval(approval)
    }

    func allowsSessionApproval(_ request: AgentCLIKit.AgentSessionApprovalRequest) async -> Bool {
        await approvalPersistenceStore.allowsSessionApproval(
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
        guard providerId == .claude else {
            return
        }
        await approvalPersistenceStore.removeSessionApprovals(
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
