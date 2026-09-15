/// App-owned persistence for reusable harness approval choices.
///
/// `AgentCLIKit` owns Claude hook transport, live hook decisions, transient fallback
/// decisions, and harness approval policy. This store keeps only Alveary's durable
/// session approvals and the user's last approval-scope selection for a harness session.
protocol ClaudeApprovalPersistenceStore: Actor {
    /// Persists a reusable approval grant and reports whether it is effective.
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult

    /// Removes a previously recorded reusable approval grant.
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async

    /// Returns whether a persisted approval grant matches any supplied harness-scoped candidate.
    func allowsSessionApproval(matching candidates: [AgentSessionApprovalGrant]) async -> Bool

    /// Returns the last selected approval scope for the harness session, when one exists.
    func toolApprovalSelection(harnessId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?

    /// Persists the last selected approval scope for the harness session.
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        harnessId: String,
        conversationId: String,
        sessionId: String
    ) async

    /// Removes reusable approvals and stored scope selections for a harness session.
    func removeSessionApprovals(harnessId: String, conversationId: String, sessionId: String) async
}
