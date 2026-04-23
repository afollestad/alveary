import Foundation

extension DefaultAgentsManager {
    func resolveToolApproval(
        conversationId: String,
        approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution,
        sessionApproval: AgentSessionApprovalGrant?,
        config: AgentSpawnConfig
    ) async throws -> Bool {
        let key = ClaudeToolApprovalKey(sessionId: approval.sessionId, toolUseId: approval.toolUseId)
        let oldPID = processes[conversationId]?.processIdentifier
        suppressExitStatus(for: conversationId, pid: oldPID)
        await teardownProcess(
            for: conversationId,
            awaitExit: true,
            preserveBufferForDurabilityGrace: false,
            graceSeconds: 1.0
        )
        await claudeHookServer.recordDecision(resolution, for: key)
        let sessionApprovalRecordResult: SessionApprovalRecordResult
        if let sessionApproval {
            sessionApprovalRecordResult = await claudeHookServer.recordSessionApproval(sessionApproval)
        } else {
            sessionApprovalRecordResult = SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }

        await MainActor.run {
            conversationState(for: conversationId).turnState.beginTurn()
        }
        updateStatus(.busy, for: conversationId)

        do {
            try await spawnImpl(id: conversationId, config: config, forkSession: false, allowReconfigureInFlight: false)
            if hookTokens[conversationId] == nil {
                await claudeHookServer.discardDecision(for: key)
                if sessionApprovalRecordResult.wasInserted, let sessionApproval {
                    await claudeHookServer.discardSessionApproval(sessionApproval)
                }
            }
            updateStatus(.busy, for: conversationId)
            return sessionApprovalRecordResult.isEffective
        } catch {
            await claudeHookServer.discardDecision(for: key)
            if sessionApprovalRecordResult.wasInserted, let sessionApproval {
                await claudeHookServer.discardSessionApproval(sessionApproval)
            }
            await MainActor.run {
                conversationState(for: conversationId).turnState.endTurn()
            }
            throw error
        }
    }
}
