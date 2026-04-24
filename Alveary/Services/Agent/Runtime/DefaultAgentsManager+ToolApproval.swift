import Foundation

extension DefaultAgentsManager {
    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool {
        let context = await makeToolApprovalResolutionContext(for: request)

        if shouldResolveToolApprovalInLiveHook(conversationId: request.conversationId) {
            markLiveToolApprovalsResolved(
                conversationId: request.conversationId,
                context: context
            )
            await recordToolApprovalDecisions(
                request.resolution,
                context: context,
                recordsTransientApprovals: false
            )
            decrementPendingLiveToolApprovals(
                conversationId: request.conversationId,
                count: context.additionalKeys.count + 1
            )
            return context.sessionApprovalRecordResult.isEffective
        }

        try await restartAgentForToolApproval(request, context: context)
        return context.sessionApprovalRecordResult.isEffective
    }

    private func restartAgentForToolApproval(
        _ request: AgentToolApprovalResolutionRequest,
        context: ToolApprovalResolutionContext
    ) async throws {
        let oldPID = processes[request.conversationId]?.processIdentifier
        suppressExitStatus(for: request.conversationId, pid: oldPID)
        await teardownProcess(
            for: request.conversationId,
            awaitExit: true,
            preserveBufferForDurabilityGrace: false,
            graceSeconds: 1.0
        )
        await recordToolApprovalDecisions(
            request.resolution,
            context: context,
            recordsTransientApprovals: true
        )

        await MainActor.run {
            conversationState(for: request.conversationId).turnState.beginTurn()
        }
        updateStatus(.busy, for: request.conversationId)

        do {
            try await spawnImpl(
                id: request.conversationId,
                config: request.config,
                forkSession: false,
                allowReconfigureInFlight: false
            )
            if hookTokens[request.conversationId] == nil {
                await discardToolApprovalResolutionContext(context)
            }
            updateStatus(.busy, for: request.conversationId)
        } catch {
            await discardToolApprovalResolutionContext(context)
            await MainActor.run {
                conversationState(for: request.conversationId).turnState.endTurn()
            }
            throw error
        }
    }

    private func makeToolApprovalResolutionContext(
        for request: AgentToolApprovalResolutionRequest
    ) async -> ToolApprovalResolutionContext {
        let additionalSessionApprovals = additionalSessionApprovals(
            for: request.additionalApprovals,
            matching: request.sessionApproval,
            conversationId: request.conversationId,
            providerId: request.config.providerId
        )
        let sessionApprovalRecordResult = await recordSessionApprovalIfNeeded(request.sessionApproval)
        let additionalSessionApprovalResults = await recordAdditionalSessionApprovals(additionalSessionApprovals)
        return ToolApprovalResolutionContext(
            request: request,
            sessionApprovalRecordResult: sessionApprovalRecordResult,
            additionalSessionApprovalResults: additionalSessionApprovalResults
        )
    }

    private func recordSessionApprovalIfNeeded(
        _ sessionApproval: AgentSessionApprovalGrant?
    ) async -> SessionApprovalRecordResult {
        guard let sessionApproval else {
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }
        return await claudeHookServer.recordSessionApproval(sessionApproval)
    }

    private func shouldResolveToolApprovalInLiveHook(conversationId: String) -> Bool {
        guard let buffer = eventBuffers[conversationId],
              buffer.pendingLiveToolApprovals > 0,
              !buffer.hasDeferredToolStop,
              processes[conversationId] != nil else {
            return false
        }
        return true
    }

    func decrementPendingLiveToolApprovals(conversationId: String, count: Int) {
        guard var buffer = eventBuffers[conversationId] else {
            return
        }
        buffer.pendingLiveToolApprovals = max(buffer.pendingLiveToolApprovals - count, 0)
        eventBuffers[conversationId] = buffer
    }

    private func markLiveToolApprovalsResolved(
        conversationId: String,
        context: ToolApprovalResolutionContext
    ) {
        guard var buffer = eventBuffers[conversationId] else {
            return
        }
        buffer.resolvedLiveToolApprovals.insert(context.key)
        buffer.resolvedLiveToolApprovals.formUnion(context.additionalKeys)
        eventBuffers[conversationId] = buffer
    }

    private func recordToolApprovalDecisions(
        _ resolution: ClaudeToolApprovalResolution,
        context: ToolApprovalResolutionContext,
        recordsTransientApprovals: Bool
    ) async {
        for additionalKey in context.additionalKeys {
            await claudeHookServer.recordDecision(resolution, for: additionalKey)
        }
        if recordsTransientApprovals {
            for additionalExactApproval in context.additionalExactApprovals {
                await claudeHookServer.recordTransientApprovalDecision(resolution, for: additionalExactApproval)
            }
        }
        await claudeHookServer.recordDecision(resolution, for: context.key)
    }

    private func additionalSessionApprovals(
        for additionalApprovals: [ToolApprovalRequest],
        matching sessionApproval: AgentSessionApprovalGrant?,
        conversationId: String,
        providerId: String
    ) -> [AgentSessionApprovalGrant] {
        guard let sessionApproval,
              let scope = sessionApproval.sessionScope else {
            return []
        }

        let approvals = additionalApprovals.compactMap {
            $0.sessionApprovalGrant(
                conversationId: conversationId,
                providerId: providerId,
                scope: scope
            )
        }
        return approvals.reduce(into: []) { result, approval in
            if approval != sessionApproval,
               !result.contains(approval) {
                result.append(approval)
            }
        }
    }

    private func recordAdditionalSessionApprovals(
        _ approvals: [AgentSessionApprovalGrant]
    ) async -> [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)] {
        var results: [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)] = []
        for approval in approvals {
            let result = await claudeHookServer.recordSessionApproval(approval)
            results.append((approval, result))
        }
        return results
    }

    private func discardInsertedSessionApprovals(
        _ results: [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)]
    ) async {
        for result in results where result.result.wasInserted {
            await claudeHookServer.discardSessionApproval(result.approval)
        }
    }

    private func discardToolApprovalResolutionContext(
        _ context: ToolApprovalResolutionContext
    ) async {
        await claudeHookServer.discardDecision(for: context.key)
        for additionalKey in context.additionalKeys {
            await claudeHookServer.discardDecision(for: additionalKey)
        }
        for additionalExactApproval in context.additionalExactApprovals {
            await claudeHookServer.discardTransientApprovalDecision(for: additionalExactApproval)
        }
        if context.sessionApprovalRecordResult.wasInserted,
           let sessionApproval = context.sessionApproval {
            await claudeHookServer.discardSessionApproval(sessionApproval)
        }
        await discardInsertedSessionApprovals(context.additionalSessionApprovalResults)
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async -> ToolApprovalSelection? {
        await claudeHookServer.toolApprovalSelection(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async {
        await claudeHookServer.recordToolApprovalSelection(
            selection,
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )
    }
}

private struct ToolApprovalResolutionContext {
    let key: ClaudeToolApprovalKey
    let additionalKeys: [ClaudeToolApprovalKey]
    let additionalExactApprovals: [AgentSessionApprovalGrant]
    let sessionApproval: AgentSessionApprovalGrant?
    let sessionApprovalRecordResult: SessionApprovalRecordResult
    let additionalSessionApprovalResults: [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)]

    init(
        request: AgentToolApprovalResolutionRequest,
        sessionApprovalRecordResult: SessionApprovalRecordResult,
        additionalSessionApprovalResults: [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)]
    ) {
        key = ClaudeToolApprovalKey(
            sessionId: request.approval.sessionId,
            toolUseId: request.approval.toolUseId
        )
        additionalKeys = request.additionalApprovals.map {
            ClaudeToolApprovalKey(sessionId: $0.sessionId, toolUseId: $0.toolUseId)
        }
        additionalExactApprovals = request.additionalApprovals.compactMap {
            $0.sessionApprovalGrant(
                conversationId: request.conversationId,
                providerId: request.config.providerId,
                scope: .exact
            )
        }
        sessionApproval = request.sessionApproval
        self.sessionApprovalRecordResult = sessionApprovalRecordResult
        self.additionalSessionApprovalResults = additionalSessionApprovalResults
    }
}

private extension AgentSessionApprovalGrant {
    var sessionScope: ToolApprovalSessionScope? {
        switch matchKind {
        case .bashExact, .filePathExact:
            return .exact
        case .bashCommandGroup:
            return .group
        }
    }
}
