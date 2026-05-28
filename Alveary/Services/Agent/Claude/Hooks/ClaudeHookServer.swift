protocol ClaudeHookServer: Actor {
    func setDeferredToolRequestHandler(
        _ handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    ) async
    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig?
    func updatePermissionMode(_ permissionMode: String?, for conversationId: String) async
    func recordDecision(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) async
    func recordTransientApprovalDecision(
        _ resolution: ClaudeToolApprovalResolution,
        for approval: AgentSessionApprovalGrant
    ) async
    func discardTransientApprovalDecision(for approval: AgentSessionApprovalGrant) async
    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult
    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async
    func allowsSessionApproval(
        providerId: String,
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) async -> Bool
    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection?
    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async
    func removeSessionApprovals(conversationId: String, sessionId: String) async
    func discardDecision(for key: ClaudeToolApprovalKey) async
    func invalidateToken(_ token: String) async
}
