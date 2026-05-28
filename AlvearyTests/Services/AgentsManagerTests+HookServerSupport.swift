import Foundation

@testable import Alveary

actor StubClaudeHookServer: ClaudeHookServer {
    enum Event: Equatable {
        case updatePermissionMode(permissionMode: String?, conversationId: String)
        case recordDecision(ClaudeToolApprovalResolution, ClaudeToolApprovalKey)
        case recordTransientApprovalDecision(ClaudeToolApprovalResolution, AgentSessionApprovalGrant)
        case discardTransientApprovalDecision(AgentSessionApprovalGrant)
        case recordSessionApproval(AgentSessionApprovalGrant)
        case discardSessionApproval(AgentSessionApprovalGrant)
        case allowsSessionApproval(providerId: String, conversationId: String, sessionId: String, toolName: String, toolInput: String)
        case recordToolApprovalSelection(ToolApprovalSelection, providerId: String, conversationId: String, sessionId: String)
        case removeSessionApprovals(conversationId: String, sessionId: String)
        case discardDecision(ClaudeToolApprovalKey)
        case invalidateToken(String)
    }

    private var launchConfigs: [ClaudeHookLaunchConfig?]
    private var recordedDecisions: [(ClaudeToolApprovalDecision, ClaudeToolApprovalKey)] = []
    private var recordedTransientApprovalDecisions: [(ClaudeToolApprovalDecision, AgentSessionApprovalGrant)] = []
    private var discardedTransientApprovalDecisions: [AgentSessionApprovalGrant] = []
    private var recordedSessionApprovals: [AgentSessionApprovalGrant] = []
    private var discardedSessionApprovalStorage: [AgentSessionApprovalGrant] = []
    private var toolApprovalSelectionStorage: [String: ToolApprovalSelection] = [:]
    private var removedSessionApprovalIDStorage: [(conversationId: String, sessionId: String)] = []
    private var discardedDecisions: [ClaudeToolApprovalKey] = []
    private var invalidatedTokens: [String] = []
    private var recordedEvents: [Event] = []
    private var deferredToolRequestHandler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    private let invalidateDelay: Duration?

    init(launchConfig: ClaudeHookLaunchConfig?, invalidateDelay: Duration? = nil) {
        self.launchConfigs = [launchConfig]
        self.invalidateDelay = invalidateDelay
    }

    init(launchConfigs: [ClaudeHookLaunchConfig?], invalidateDelay: Duration? = nil) {
        self.launchConfigs = launchConfigs
        self.invalidateDelay = invalidateDelay
    }

    func setDeferredToolRequestHandler(
        _ handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    ) {
        deferredToolRequestHandler = handler
    }

    func emitDeferredToolRequest(_ request: ClaudeDeferredToolRequest) async {
        await deferredToolRequestHandler?(request)
    }

    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig? {
        guard launchConfigs.count > 1 else {
            return launchConfigs.first ?? nil
        }
        return launchConfigs.removeFirst()
    }

    func updatePermissionMode(_ permissionMode: String?, for conversationId: String) async {
        recordedEvents.append(.updatePermissionMode(permissionMode: permissionMode, conversationId: conversationId))
    }

    func recordDecision(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) async {
        recordedDecisions.append((resolution.decision, key))
        recordedEvents.append(.recordDecision(resolution, key))
    }

    func recordTransientApprovalDecision(
        _ resolution: ClaudeToolApprovalResolution,
        for approval: AgentSessionApprovalGrant
    ) async {
        recordedTransientApprovalDecisions.append((resolution.decision, approval))
        recordedEvents.append(.recordTransientApprovalDecision(resolution, approval))
    }

    func transientApprovalDecisions() -> [(ClaudeToolApprovalDecision, AgentSessionApprovalGrant)] {
        recordedTransientApprovalDecisions
    }

    func discardTransientApprovalDecision(for approval: AgentSessionApprovalGrant) async {
        discardedTransientApprovalDecisions.append(approval)
        recordedEvents.append(.discardTransientApprovalDecision(approval))
    }

    func discardedTransientApprovals() -> [AgentSessionApprovalGrant] {
        discardedTransientApprovalDecisions
    }

    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult {
        recordedSessionApprovals.append(approval)
        recordedEvents.append(.recordSessionApproval(approval))
        return SessionApprovalRecordResult(isEffective: true, wasInserted: true)
    }

    func sessionApprovals() -> [AgentSessionApprovalGrant] {
        recordedSessionApprovals
    }

    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async {
        discardedSessionApprovalStorage.append(approval)
        recordedEvents.append(.discardSessionApproval(approval))
    }

    func discardedSessionApprovals() -> [AgentSessionApprovalGrant] {
        discardedSessionApprovalStorage
    }

    func allowsSessionApproval(
        providerId: String,
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) async -> Bool {
        recordedEvents.append(.allowsSessionApproval(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput
        ))
        return recordedSessionApprovals.contains { approval in
            approval.providerId == providerId &&
                approval.conversationId == conversationId &&
                approval.sessionId == sessionId
        }
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) -> ToolApprovalSelection? {
        toolApprovalSelectionStorage[toolApprovalSelectionKey(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )]
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) {
        toolApprovalSelectionStorage[toolApprovalSelectionKey(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )] = selection
        recordedEvents.append(
            .recordToolApprovalSelection(
                selection,
                providerId: providerId,
                conversationId: conversationId,
                sessionId: sessionId
            )
        )
    }

    func removeSessionApprovals(conversationId: String, sessionId: String) async {
        removedSessionApprovalIDStorage.append((conversationId: conversationId, sessionId: sessionId))
        recordedEvents.append(.removeSessionApprovals(conversationId: conversationId, sessionId: sessionId))
    }

    func removedSessionApprovalIDs() -> [(conversationId: String, sessionId: String)] {
        removedSessionApprovalIDStorage
    }

    func decisions() -> [(ClaudeToolApprovalDecision, ClaudeToolApprovalKey)] {
        recordedDecisions
    }

    func discardDecision(for key: ClaudeToolApprovalKey) {
        discardedDecisions.append(key)
        recordedEvents.append(.discardDecision(key))
    }

    func discards() -> [ClaudeToolApprovalKey] {
        discardedDecisions
    }

    func invalidateToken(_ token: String) async {
        if let invalidateDelay {
            try? await Task.sleep(for: invalidateDelay)
        }
        invalidatedTokens.append(token)
        recordedEvents.append(.invalidateToken(token))
    }

    func invalidations() -> [String] {
        invalidatedTokens
    }

    func events() -> [Event] {
        recordedEvents
    }

    private func toolApprovalSelectionKey(providerId: String, conversationId: String, sessionId: String) -> String {
        "\(providerId)|\(conversationId)|\(sessionId)"
    }
}
