/// No-op approval persistence used by tests or previews that should not touch disk.
actor DisabledClaudeApprovalPersistenceStore: ClaudeApprovalPersistenceStore {
    /// Creates a disabled persistence store.
    init() {}

    /// Reports that no session approval was recorded.
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult {
        SessionApprovalRecordResult(isEffective: false, wasInserted: false)
    }

    /// Ignores approval removal.
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async {}

    /// Always reports that no reusable approval covers the request.
    func allowsSessionApproval(matching candidates: [AgentSessionApprovalGrant]) async -> Bool {
        false
    }

    /// Always reports that no approval selection exists.
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection? {
        nil
    }

    /// Ignores approval-selection writes.
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async {}

    /// Ignores approval cleanup.
    func removeSessionApprovals(providerId: String, conversationId: String, sessionId: String) async {}
}
