import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool {
        let context = await makeToolApprovalResolutionContext(for: request)
        let services = agentCLIKitServices

        do {
            let approvals = [request.approval] + request.additionalApprovals
            let liveResolutionCount = await resolveAgentCLIKitLiveHookApprovals(
                approvals,
                resolution: request.resolution,
                conversationId: request.conversationId,
                services: services
            )
            if liveResolutionCount > 0 {
                markLiveToolApprovalsResolved(
                    conversationId: request.conversationId,
                    context: context
                )
                decrementPendingLiveToolApprovals(
                    conversationId: request.conversationId,
                    count: liveResolutionCount
                )
                return finishAgentCLIKitToolApprovalResolution(request, context: context)
            }

            if await canResumeAgentCLIKitDeferredApproval(
                conversationId: request.conversationId,
                services: services
            ) {
                try await resumeAgentCLIKitDeferredApproval(
                    request,
                    approvals: approvals,
                    services: services
                )
                return finishAgentCLIKitToolApprovalResolution(request, context: context)
            }

            for approval in approvals {
                try await services.runtime.resolveInteraction(
                    try agentCLIKitInteractionResolution(for: approval, resolution: request.resolution),
                    conversationId: services.hostAdapter.conversationId(request.conversationId)
                )
            }
        } catch {
            await discardToolApprovalResolutionContext(context)
            throw error
        }

        return finishAgentCLIKitToolApprovalResolution(request, context: context)
    }

    private func finishAgentCLIKitToolApprovalResolution(
        _ request: AgentToolApprovalResolutionRequest,
        context: ToolApprovalResolutionContext
    ) -> Bool {
        recordDeniedToolUseIdsIfNeeded(request)
        let didCancelAskUserQuestion = recordCancelledPromptResolutionIfNeeded(request)
        eventBuffers[request.conversationId]?.hasSentPendingUserActionNotification = false
        updateStatus(didCancelAskUserQuestion ? .idle : .busy, for: request.conversationId)
        return context.sessionApprovalRecordResult.isEffective
    }

    private func resolveAgentCLIKitLiveHookApprovals(
        _ approvals: [ToolApprovalRequest],
        resolution: ClaudeToolApprovalResolution,
        conversationId: String,
        services: AgentCLIKitHostServices
    ) async -> Int {
        var count = 0
        var unresolvedKeys: [ClaudeToolApprovalKey] = []
        for approval in approvals {
            let key = ClaudeToolApprovalKey(sessionId: approval.sessionId, toolUseId: approval.toolUseId)
            if await services.liveHookDecisionProvider.resolve(resolution, for: key) {
                count += 1
            } else {
                unresolvedKeys.append(key)
            }
        }
        if count > 0 {
            for key in unresolvedKeys {
                await services.liveHookDecisionProvider.recordFutureResolution(
                    resolution,
                    for: key,
                    conversationId: conversationId
                )
            }
        }
        return count
    }

    func agentCLIKitInteractionResolution(
        for approval: ToolApprovalRequest,
        resolution: ClaudeToolApprovalResolution
    ) throws -> AgentCLIKit.AgentInteractionResolution {
        var metadata: [String: AgentCLIKit.JSONValue] = [
            "approval_decision": .string(resolution.decision.rawValue)
        ]
        if let updatedInput = resolution.updatedInput {
            metadata["updated_input"] = try agentCLIKitJSONValue(from: updatedInput)
        }

        return AgentCLIKit.AgentInteractionResolution(
            id: AgentCLIKit.AgentInteractionID(rawValue: approval.toolUseId),
            outcome: agentCLIKitOutcome(for: approval, decision: resolution.decision),
            metadata: metadata
        )
    }

    func agentCLIKitOutcome(
        for approval: ToolApprovalRequest,
        decision: ClaudeToolApprovalDecision
    ) -> AgentCLIKit.AgentInteractionOutcome {
        switch (approval.toolName, decision) {
        case ("AskUserQuestion", .allow):
            return .answered
        case ("AskUserQuestion", .deny):
            return .cancelled
        case (_, .allow):
            return .approved
        case (_, .deny):
            return .denied
        }
    }

    func agentCLIKitJSONValue(from string: String) throws -> AgentCLIKit.JSONValue {
        guard let data = string.data(using: .utf8) else {
            throw AgentError.spawnFailed("Updated tool input is not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data)
        } catch {
            throw AgentError.spawnFailed("Updated tool input is not valid JSON: \(error.localizedDescription)")
        }
    }

    private func recordDeniedToolUseIdsIfNeeded(_ request: AgentToolApprovalResolutionRequest) {
        guard request.resolution.decision == .deny else {
            return
        }

        var deniedToolUseIds = deniedToolUseIdsByConversation[request.conversationId] ?? []
        deniedToolUseIds.insert(request.approval.toolUseId)
        deniedToolUseIds.formUnion(request.additionalApprovals.map(\.toolUseId))
        deniedToolUseIdsByConversation[request.conversationId] = deniedToolUseIds
    }

    private func recordCancelledPromptResolutionIfNeeded(_ request: AgentToolApprovalResolutionRequest) -> Bool {
        guard request.approval.toolName == "AskUserQuestion",
              request.resolution.decision == .deny else {
            cancelledPromptResolutionsByConversation.removeValue(forKey: request.conversationId)
            return false
        }

        cancelledPromptResolutionsByConversation[request.conversationId] = CancelledPromptResolution(
            toolUseId: request.approval.toolUseId,
            agentGeneration: agentCLIKitStatuses[request.conversationId]?.generation
                ?? agentCLIKitGenerationByConversation[request.conversationId]
        )
        return true
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
        guard let agentCLIKitApproval = agentCLIKitSessionApproval(sessionApproval) else {
            return SessionApprovalRecordResult(isEffective: false, wasInserted: false)
        }
        let result = await agentCLIKitServices.claudeApprovalPolicyStore.recordSessionApproval(agentCLIKitApproval)
        return SessionApprovalRecordResult(isEffective: result.isEffective, wasInserted: result.wasInserted)
    }

    func decrementPendingLiveToolApprovals(conversationId: String, count: Int) {
        guard let buffer = eventBuffers[conversationId] else {
            return
        }
        buffer.pendingLiveToolApprovals = max(buffer.pendingLiveToolApprovals - count, 0)
    }

    private func markLiveToolApprovalsResolved(
        conversationId: String,
        context: ToolApprovalResolutionContext
    ) {
        guard let buffer = eventBuffers[conversationId] else {
            return
        }
        buffer.resolvedLiveToolApprovals.insert(context.key)
        buffer.resolvedLiveToolApprovals.formUnion(context.additionalKeys)
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
            let result = await recordSessionApprovalIfNeeded(approval)
            results.append((approval, result))
        }
        return results
    }

    private func discardInsertedSessionApprovals(
        _ results: [(approval: AgentSessionApprovalGrant, result: SessionApprovalRecordResult)]
    ) async {
        for result in results where result.result.wasInserted {
            await discardSessionApproval(result.approval)
        }
    }

    private func discardToolApprovalResolutionContext(
        _ context: ToolApprovalResolutionContext
    ) async {
        let services = agentCLIKitServices
        await services.liveHookDecisionProvider.discardDecision(for: context.key)
        for additionalKey in context.additionalKeys {
            await services.liveHookDecisionProvider.discardDecision(for: additionalKey)
        }
        if context.sessionApprovalRecordResult.wasInserted,
           let sessionApproval = context.sessionApproval {
            await discardSessionApproval(sessionApproval)
        }
        await discardInsertedSessionApprovals(context.additionalSessionApprovalResults)
    }

    private func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async {
        guard let agentCLIKitApproval = agentCLIKitSessionApproval(approval) else {
            return
        }
        await agentCLIKitServices.claudeApprovalPolicyStore.discardSessionApproval(agentCLIKitApproval)
    }

    private func agentCLIKitSessionApproval(
        _ approval: AgentSessionApprovalGrant
    ) -> AgentCLIKit.AgentSessionApprovalGrant? {
        guard let providerId = agentCLIKitServices.hostAdapter.providerId(approval.providerId),
              let matchKind = AgentCLIKit.AgentSessionApprovalMatchKind(rawValue: approval.matchKind.rawValue) else {
            return nil
        }
        return AgentCLIKit.AgentSessionApprovalGrant(
            providerId: providerId,
            conversationId: AgentCLIKit.AgentConversationID(rawValue: approval.conversationId),
            sessionId: AgentCLIKit.AgentSessionID(rawValue: approval.sessionId),
            matchKind: matchKind,
            matchValue: approval.matchValue
        )
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async -> ToolApprovalSelection? {
        await claudeApprovalPersistenceStore.toolApprovalSelection(
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
        await claudeApprovalPersistenceStore.recordToolApprovalSelection(
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
