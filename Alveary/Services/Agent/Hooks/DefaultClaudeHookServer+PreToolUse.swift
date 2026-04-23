import Foundation

struct ClaudePreToolUsePayload {
    let launchContext: HookLaunchContext
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
                sessionId: sessionId,
                toolUseId: toolUseId,
                toolName: toolName,
                rawToolInput: payload["tool_input"],
                permissionMode: permissionMode
            )
        )
    }

    func handlePreToolUsePayload(_ payload: ClaudePreToolUsePayload) -> ClaudeHookHTTPResponse {
        let key = ClaudeToolApprovalKey(sessionId: payload.sessionId, toolUseId: payload.toolUseId)
        if let decision = decisions.removeValue(forKey: key) {
            let updatedInput = updatedInputs.removeValue(forKey: key)
            return decisionResponse(
                decision,
                reason: reason(for: decision),
                toolName: payload.toolName,
                rawToolInput: payload.rawToolInput,
                updatedInput: deserializedJSONObject(from: updatedInput)
            )
        }

        if let toolInput = serializedToolInput(payload.rawToolInput),
           shouldAllowForStoredSessionApproval(
               conversationId: payload.launchContext.conversationId,
               sessionId: payload.sessionId,
               toolName: payload.toolName,
               toolInput: toolInput
           ) {
            return decisionResponse(
                .allow,
                reason: "Approved for session in Alveary",
                toolName: payload.toolName,
                rawToolInput: payload.rawToolInput
            )
        }

        guard ClaudeHookPolicy.shouldDefer(
            toolName: payload.toolName,
            permissionMode: payload.permissionMode
        ) else {
            return .empty()
        }

        return decisionResponse(.defer)
    }
}
