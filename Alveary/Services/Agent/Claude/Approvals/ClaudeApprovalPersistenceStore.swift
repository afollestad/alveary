/// App-owned persistence for reusable Claude approval choices.
///
/// `AgentCLIKit` owns Claude hook transport, live hook decisions, transient fallback
/// decisions, and provider approval policy. This store keeps only Alveary's durable
/// session approvals and the user's last approval-scope selection for a Claude session.
protocol ClaudeApprovalPersistenceStore: Actor {
    /// Persists a reusable approval grant and reports whether it is effective.
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult

    /// Removes a previously recorded reusable approval grant.
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async

    /// Returns whether a persisted approval grant covers the supplied Claude tool request.
    func allowsSessionApproval(
        providerId: String,
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) async -> Bool

    /// Returns the last selected approval scope for the Claude session, when one exists.
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?

    /// Persists the last selected approval scope for the Claude session.
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async

    /// Removes reusable approvals and stored scope selections for a Claude session.
    func removeSessionApprovals(conversationId: String, sessionId: String) async
}
