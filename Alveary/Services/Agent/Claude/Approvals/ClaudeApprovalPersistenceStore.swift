/// App-owned persistence for reusable provider approval choices.
///
/// `AgentCLIKit` owns Claude hook transport, live hook decisions, transient fallback
/// decisions, and provider approval policy. This store keeps only Alveary's durable
/// session approvals and the user's last approval-scope selection for a provider session.
protocol ClaudeApprovalPersistenceStore: Actor {
    /// Persists a reusable approval grant and reports whether it is effective.
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult

    /// Removes a previously recorded reusable approval grant.
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async

    /// Returns whether a persisted approval grant matches any supplied provider-scoped candidate.
    func allowsSessionApproval(matching candidates: [AgentSessionApprovalGrant]) async -> Bool

    /// Returns the last selected approval scope for the provider session, when one exists.
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?

    /// Persists the last selected approval scope for the provider session.
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async

    /// Removes reusable approvals and stored scope selections for a provider session.
    func removeSessionApprovals(providerId: String, conversationId: String, sessionId: String) async
}
