import AgentCLIKit
import Foundation

actor AgentCLIKitLiveHookDecisionProvider: AgentCLIKit.ClaudeHookDecisionProviding {
    private let publishDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    private var continuations: [ClaudeToolApprovalKey: CheckedContinuation<AgentCLIKit.ClaudeHookDecision, Never>] = [:]
    private var toolInputs: [ClaudeToolApprovalKey: AgentCLIKit.JSONValue] = [:]
    private var toolNames: [ClaudeToolApprovalKey: String] = [:]
    private var requestIDs: [ClaudeToolApprovalKey: UUID] = [:]
    private var futureResolutions: [ClaudeToolApprovalKey: ClaudeToolApprovalResolution] = [:]
    private var conversationIds: [ClaudeToolApprovalKey: String] = [:]

    init(
        publishDelay: Duration = .milliseconds(50),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.publishDelay = publishDelay
        self.sleep = sleep
    }

    func setDeferredToolRequestHandler(
        _ handler: (@Sendable (ClaudeDeferredToolRequest) async -> Void)?
    ) {
        self.handler = handler
    }

    func decision(
        for request: AgentCLIKit.ClaudeHookRequest,
        interactionId: AgentCLIKit.AgentInteractionID
    ) async -> AgentCLIKit.ClaudeHookDecision {
        guard let handler,
              let toolApprovalRequest = Self.toolApprovalRequest(from: request, interactionId: interactionId) else {
            return .deferDecision
        }

        let key = ClaudeToolApprovalKey(
            sessionId: toolApprovalRequest.sessionId,
            toolUseId: toolApprovalRequest.toolUseId
        )
        conversationIds[key] = request.conversationId.rawValue
        toolInputs[key] = Self.toolInput(from: request)
        toolNames[key] = toolApprovalRequest.toolName
        if let resolution = futureResolutions.removeValue(forKey: key) {
            let decision = hookDecision(from: resolution, for: key)
            clearState(for: key)
            return decision
        }
        let requestID = UUID()
        requestIDs[key] = requestID
        let deferredToolRequest = ClaudeDeferredToolRequest(
            conversationId: request.conversationId.rawValue,
            request: toolApprovalRequest
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let existing = continuations.updateValue(continuation, forKey: key) {
                    existing.resume(returning: .deferDecision)
                }
                Task {
                    await self.publishAfterDelayIfPending(
                        deferredToolRequest,
                        for: key,
                        requestID: requestID,
                        handler: handler
                    )
                }
            }
        } onCancel: {
            Task {
                await self.cancelDecision(for: key)
            }
        }
    }

    func resolve(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) -> Bool {
        guard let continuation = continuations.removeValue(forKey: key) else {
            return false
        }
        continuation.resume(returning: hookDecision(from: resolution, for: key))
        clearState(for: key)
        return true
    }

    func recordFutureResolution(
        _ resolution: ClaudeToolApprovalResolution,
        for key: ClaudeToolApprovalKey,
        conversationId: String? = nil
    ) {
        if let conversationId {
            conversationIds[key] = conversationId
        }
        if let continuation = continuations.removeValue(forKey: key) {
            continuation.resume(returning: hookDecision(from: resolution, for: key))
            clearState(for: key)
            return
        }
        futureResolutions[key] = resolution
    }

    func discardDecision(for key: ClaudeToolApprovalKey) {
        guard let continuation = continuations.removeValue(forKey: key) else {
            futureResolutions.removeValue(forKey: key)
            clearState(for: key)
            return
        }
        continuation.resume(returning: .deferDecision)
        futureResolutions.removeValue(forKey: key)
        clearState(for: key)
    }

    func discardDecisions(conversationId: String) {
        let keys = conversationIds.compactMap { key, storedConversationId in
            storedConversationId == conversationId ? key : nil
        }
        for key in keys {
            discardDecision(for: key)
        }
    }

    private func cancelDecision(for key: ClaudeToolApprovalKey) {
        guard let continuation = continuations.removeValue(forKey: key) else {
            return
        }
        continuation.resume(returning: .deferDecision)
        clearState(for: key)
    }

    private func clearState(for key: ClaudeToolApprovalKey) {
        toolInputs.removeValue(forKey: key)
        toolNames.removeValue(forKey: key)
        requestIDs.removeValue(forKey: key)
        conversationIds.removeValue(forKey: key)
    }

    private func publishAfterDelayIfPending(
        _ request: ClaudeDeferredToolRequest,
        for key: ClaudeToolApprovalKey,
        requestID: UUID,
        handler: @Sendable (ClaudeDeferredToolRequest) async -> Void
    ) async {
        do {
            // Match the legacy hook-server delay so preceding tool_call rows can render before the approval row.
            try await sleep(publishDelay)
        } catch {
            return
        }
        await publishIfPending(
            request,
            for: key,
            requestID: requestID,
            handler: handler
        )
    }

    private func publishIfPending(
        _ request: ClaudeDeferredToolRequest,
        for key: ClaudeToolApprovalKey,
        requestID: UUID,
        handler: @Sendable (ClaudeDeferredToolRequest) async -> Void
    ) async {
        guard requestIDs[key] == requestID,
              continuations[key] != nil else {
            return
        }
        await handler(request)
    }

    private func hookDecision(
        from resolution: ClaudeToolApprovalResolution,
        for key: ClaudeToolApprovalKey
    ) -> AgentCLIKit.ClaudeHookDecision {
        switch resolution.decision {
        case .allow:
            return .allow(
                reason: "The user approved this permission prompt in Alveary",
                updatedInput: updatedInput(for: key, resolution: resolution)
            )
        case .deny:
            return .deny(reason: "The user denied this permission prompt in Alveary")
        }
    }

    private func updatedInput(
        for key: ClaudeToolApprovalKey,
        resolution: ClaudeToolApprovalResolution
    ) -> AgentCLIKit.JSONValue? {
        if let updatedInput = resolution.updatedInput.flatMap(Self.jsonValue(from:)) {
            return updatedInput
        }
        guard let toolName = toolNames[key],
              Self.requiresUpdatedInput(toolName: toolName) else {
            return nil
        }
        return toolInputs[key]
    }

    private static func toolApprovalRequest(
        from request: AgentCLIKit.ClaudeHookRequest,
        interactionId: AgentCLIKit.AgentInteractionID
    ) -> ToolApprovalRequest? {
        guard case let .object(payload) = request.payload,
              let sessionId = payload.stringValue("session_id") ?? payload.stringValue("sessionId") else {
            return nil
        }
        let toolName = payload.stringValue("tool_name") ?? payload.stringValue("toolName") ?? "tool"
        let toolInput = payload["tool_input"] ?? payload["toolInput"] ?? .object([:])
        return ToolApprovalRequest(
            sessionId: sessionId,
            toolUseId: interactionId.rawValue,
            toolName: toolName,
            toolInput: serialized(toolInput),
            planMarkdownFallback: toolName == "ExitPlanMode" ? toolInput.stringValue("plan") : nil
        )
    }

    private static func toolInput(from request: AgentCLIKit.ClaudeHookRequest) -> AgentCLIKit.JSONValue {
        guard case let .object(payload) = request.payload else {
            return .object([:])
        }
        return payload["tool_input"] ?? payload["toolInput"] ?? .object([:])
    }

    private static func requiresUpdatedInput(toolName: String) -> Bool {
        toolName == "AskUserQuestion" || toolName == "ExitPlanMode"
    }

    private static func jsonValue(from string: String) -> AgentCLIKit.JSONValue? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentCLIKit.JSONValue.self, from: data)
    }

    private static func serialized(_ value: AgentCLIKit.JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private extension [String: AgentCLIKit.JSONValue] {
    func stringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else {
            return nil
        }
        return value
    }
}

private extension AgentCLIKit.JSONValue {
    func stringValue(_ key: String) -> String? {
        guard case let .object(object) = self,
              case let .string(value)? = object[key] else {
            return nil
        }
        return value
    }
}
