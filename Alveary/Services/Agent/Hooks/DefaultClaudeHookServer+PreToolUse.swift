import Foundation

struct ClaudePreToolUsePayload {
    let launchContext: HookLaunchContext
    let launchToken: String
    let sessionId: String
    let toolUseId: String
    let toolName: String
    let rawToolInput: Any?
    let permissionMode: String?
}

enum ClaudePreToolUseValidation {
    case payload(ClaudePreToolUsePayload)
    case response(ClaudeHookHTTPResponse)
}

extension DefaultClaudeHookServer {
    func validatedPreToolUsePayload(
        from request: ClaudeHookHTTPRequest
    ) -> ClaudePreToolUseValidation {
        guard let token = authorizationToken(from: request.authorization),
              validTokens.contains(token),
              let launchContext = launchContextByToken[token] else {
            return .response(decisionResponse(.deny, reason: "Invalid Alveary hook token"))
        }

        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return .response(decisionResponse(.deny, reason: "Invalid Alveary hook request"))
        }

        guard let hookEventName = payload["hook_event_name"] as? String else {
            return .response(decisionResponse(.deny, reason: "Incomplete Alveary hook request"))
        }

        guard hookEventName == "PreToolUse" else {
            return .response(.empty())
        }

        guard let sessionId = payload["session_id"] as? String,
              let toolUseId = payload["tool_use_id"] as? String,
              let toolName = payload["tool_name"] as? String else {
            return .response(decisionResponse(.deny, reason: "Incomplete Alveary hook request"))
        }

        let permissionMode = payload["permission_mode"] as? String
            ?? livePermissionModeByConversation[launchContext.conversationId]
            ?? launchContext.permissionMode

        return .payload(
            ClaudePreToolUsePayload(
                launchContext: launchContext,
                launchToken: token,
                sessionId: sessionId,
                toolUseId: toolUseId,
                toolName: toolName,
                rawToolInput: payload["tool_input"],
                permissionMode: permissionMode
            )
        )
    }

    func handlePreToolUsePayload(_ payload: ClaudePreToolUsePayload) async -> ClaudeHookHTTPResponse {
        let key = ClaudeToolApprovalKey(sessionId: payload.sessionId, toolUseId: payload.toolUseId)
        if let response = recordedDecisionResponse(for: key, payload: payload) {
            return response
        }

        let toolInput = serializedToolInput(payload.rawToolInput)
        let approvalRequest = ToolApprovalRequest(
            sessionId: payload.sessionId,
            toolUseId: payload.toolUseId,
            toolName: payload.toolName,
            toolInput: toolInput ?? "{}"
        )
        guard ClaudeHookPolicy.shouldDefer(
            toolName: payload.toolName,
            permissionMode: payload.permissionMode
        ) else {
            return .empty()
        }

        if let response = preDeferredApprovalResponse(
            payload: payload,
            approvalRequest: approvalRequest,
            toolInput: toolInput
        ) {
            return response
        }

        guard scheduleDeferredToolRequestNotification(payload) else {
            return decisionResponse(.defer)
        }
        if let resolution = await waitForPendingApprovalDecision(
            for: key,
            launchToken: payload.launchToken
        ) {
            return decisionResponse(
                resolution.decision,
                reason: reason(for: resolution.decision),
                toolName: payload.toolName,
                rawToolInput: payload.rawToolInput,
                updatedInput: deserializedJSONObject(from: resolution.updatedInput)
            )
        }
        return decisionResponse(.defer)
    }

    private func preDeferredApprovalResponse(
        payload: ClaudePreToolUsePayload,
        approvalRequest: ToolApprovalRequest,
        toolInput: String?
    ) -> ClaudeHookHTTPResponse? {
        if let transientDecision = transientApprovalDecision(
            for: approvalRequest,
            conversationId: payload.launchContext.conversationId
        ) {
            return decisionResponse(
                transientDecision,
                reason: transientReason(for: transientDecision),
                toolName: payload.toolName,
                rawToolInput: payload.rawToolInput
            )
        }

        guard let toolInput,
              shouldAllowForStoredSessionApproval(
                  conversationId: payload.launchContext.conversationId,
                  sessionId: payload.sessionId,
                  toolName: payload.toolName,
                  toolInput: toolInput
              ) else {
            return nil
        }
        return decisionResponse(
            .allow,
            reason: "Approved for session in Alveary",
            toolName: payload.toolName,
            rawToolInput: payload.rawToolInput
        )
    }

    private func recordedDecisionResponse(
        for key: ClaudeToolApprovalKey,
        payload: ClaudePreToolUsePayload
    ) -> ClaudeHookHTTPResponse? {
        guard let decision = decisions.removeValue(forKey: key) else {
            return nil
        }

        let updatedInput = updatedInputs.removeValue(forKey: key)
        return decisionResponse(
            decision,
            reason: reason(for: decision),
            toolName: payload.toolName,
            rawToolInput: payload.rawToolInput,
            updatedInput: deserializedJSONObject(from: updatedInput)
        )
    }

    private func transientApprovalDecision(
        for request: ToolApprovalRequest,
        conversationId: String
    ) -> ClaudeToolApprovalDecision? {
        guard let approval = request.sessionApprovalGrant(
            conversationId: conversationId,
            providerId: "claude",
            scope: .exact
        ) else {
            return nil
        }
        return transientApprovalDecisions.removeValue(forKey: approval)
    }

    private func transientReason(for decision: ClaudeToolApprovalDecision) -> String {
        switch decision {
        case .allow:
            return "Approved once as part of the same Alveary permission batch"
        case .deny:
            return "Denied once as part of the same Alveary permission batch"
        }
    }

    private func scheduleDeferredToolRequestNotification(_ payload: ClaudePreToolUsePayload) -> Bool {
        guard let deferredToolRequestHandler else {
            return false
        }

        let request = ToolApprovalRequest(
            sessionId: payload.sessionId,
            toolUseId: payload.toolUseId,
            toolName: payload.toolName,
            toolInput: serializedToolInput(payload.rawToolInput) ?? "{}"
        )
        let deferredToolRequest = ClaudeDeferredToolRequest(
            conversationId: payload.launchContext.conversationId,
            launchToken: payload.launchToken,
            request: request
        )
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            await deferredToolRequestHandler(deferredToolRequest)
        }
        return true
    }
}
