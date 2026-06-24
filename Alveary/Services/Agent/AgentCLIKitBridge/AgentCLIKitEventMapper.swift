import AgentCLIKit
import Foundation

struct AgentCLIKitEventMapper: Sendable {
    // swiftlint:disable:next cyclomatic_complexity
    func conversationEvents(from envelope: AgentCLIKit.AgentEventEnvelope) -> [ConversationEvent] {
        switch envelope.event {
        case .message(let event):
            return messageEvents(from: event)
        case .messageDelta(let event):
            return messageDeltaEvents(from: event)
        case .reasoning(let event):
            return reasoningEvents(from: event)
        case .toolCall(let event):
            return toolCallEvents(from: event)
        case .toolResult(let event):
            return toolResultEvents(from: event)
        case .subAgent(let event):
            return subAgentEvents(from: event)
        case .usage(let event):
            return usageEvents(from: event)
        case .permissionMode(let event):
            return [.permissionModeChanged(event.mode)]
        case .collaborationMode(let event):
            return [.collaborationModeChanged(event.mode == .plan)]
        case .task(let event):
            return taskEvents(from: event, envelope: envelope)
        case .goal(let event):
            return [.goal(event)]
        case .contextCompaction(let event):
            return contextCompactionEvents(from: event)
        case .sessionMetadata(let event):
            return [.providerSessionMetadataChanged(
                sessionId: event.providerSessionId?.rawValue,
                name: event.name,
                preview: event.preview
            )]
        case .sessionContinuity(let event):
            return [.sessionInit(sessionId: event.providerSessionId?.rawValue)]
        case .interaction(let event):
            return interactionEvents(from: event, providerSessionId: envelope.providerSessionId?.rawValue)
        case .lifecycle(let event):
            return lifecycleEvents(from: event)
        case .diagnostic(let event):
            return diagnosticEvents(from: event)
        case .rateLimit(let event):
            return [.notification(type: "rate_limit", message: event.status.rawValue)]
        case .activity(let event):
            return activityEvents(from: event, envelope: envelope)
        case .rawOutput:
            return []
        }
    }

    private func messageEvents(from event: AgentCLIKit.AgentMessageEvent) -> [ConversationEvent] {
        if let steeredConversation = steeredConversationEvent(from: event) {
            return [steeredConversation]
        }
        if event.role == .user,
           event.metadata.stringValue("agent_plan_exit_interaction_id") != nil {
            return [.runtimeUserMessage(content: event.text)]
        }
        return [.message(
            role: event.role.rawValue,
            content: event.text,
            parentToolUseId: event.metadata.stringValue("parent_tool_use_id")
        )]
    }

    private func steeredConversationEvent(from event: AgentCLIKit.AgentMessageEvent) -> ConversationEvent? {
        guard event.role == .user,
              event.metadata.boolValue(AgentCLIKit.AgentSteeringMetadata.isSteering) == true,
              let signal = event.metadata.stringValue(AgentCLIKit.AgentSteeringMetadata.signal),
              Self.isSteeringSignal(signal),
              let inputID = event.metadata.stringValue(AgentCLIKit.AgentSteeringMetadata.inputId) else {
            return nil
        }
        return .steeredConversation(inputID: inputID)
    }

    private static func isSteeringSignal(_ signal: String) -> Bool {
        switch signal {
        case AgentCLIKit.AgentSteeringMetadata.signalCodexUserMessageStarted,
             AgentCLIKit.AgentSteeringMetadata.signalCodexUserMessageCompleted,
             AgentCLIKit.AgentSteeringMetadata.signalRuntimeInputAccepted:
            return true
        default:
            return false
        }
    }

    private func messageDeltaEvents(from event: AgentCLIKit.AgentMessageDeltaEvent) -> [ConversationEvent] {
        [.messageChunk(
            text: event.text,
            parentToolUseId: event.metadata.stringValue("parent_tool_use_id")
        )]
    }

    private func reasoningEvents(from event: AgentCLIKit.AgentReasoningEvent) -> [ConversationEvent] {
        guard event.metadata.stringValue("codex_item_phase")?.lowercased() != "completed" else {
            return []
        }
        return [.thinking(
            content: event.text,
            parentToolUseId: event.metadata.stringValue("parent_tool_use_id")
        )]
    }

    private func toolCallEvents(from event: AgentCLIKit.AgentToolCallEvent) -> [ConversationEvent] {
        [.toolCall(
            id: event.id,
            name: event.name,
            input: Self.serialized(event.input),
            parentToolUseId: event.metadata.stringValue("parent_tool_use_id"),
            callerAgent: event.metadata.stringValue("caller_agent")
        )]
    }

    private func toolResultEvents(from event: AgentCLIKit.AgentToolResultEvent) -> [ConversationEvent] {
        [.toolResult(
            id: event.id,
            output: event.content,
            isError: event.isError,
            parentToolUseId: event.metadata.stringValue("parent_tool_use_id"),
            metadata: ToolResultMetadata(
                stderr: event.metadata.stringValue("stderr"),
                interrupted: event.metadata.boolValue("interrupted") ?? false,
                isImage: event.metadata.boolValue("is_image") ?? false,
                noOutputExpected: event.metadata.boolValue("no_output_expected") ?? false
            )
        )]
    }

    private func usageEvents(from event: AgentCLIKit.AgentUsageEvent) -> [ConversationEvent] {
        let stopReason = event.stopReason ?? event.metadata.stringValue("stop_reason")
        let permissionDenials = event.permissionDenials.map {
            PermissionDenialSummary(toolName: $0.toolName ?? "Unknown tool", toolUseId: $0.toolUseId)
        }
        let tokenEvent = ConversationEvent.tokens(
            input: event.inputTokens ?? 0,
            output: event.outputTokens ?? 0,
            // `cachedInputTokens` is already included in input tokens; only additive cache-read tokens persist here.
            cacheRead: event.cacheReadInputTokens ?? 0,
            cacheCreation: event.cacheCreationInputTokens ?? 0,
            isError: event.isError,
            stopReason: stopReason,
            durationMs: event.durationMs ?? 0,
            costUsd: event.costUSD,
            providerModelId: event.model,
            contextWindowSize: event.contextWindow,
            permissionDenials: permissionDenials,
            isTerminal: event.isTerminal || Self.isTerminalStopReason(stopReason)
        )
        return [tokenEvent]
    }

    private static func isTerminalStopReason(_ stopReason: String?) -> Bool {
        guard let stopReason,
              stopReason != AgentCLIKit.AgentUsageEvent.interimUsageStopReason,
              stopReason != "tool_use",
              stopReason != "tool_deferred" else {
            return false
        }
        return true
    }

    private func taskEvents(
        from event: AgentCLIKit.AgentTaskEvent,
        envelope: AgentCLIKit.AgentEventEnvelope
    ) -> [ConversationEvent] {
        if let taskListSnapshotEvent = taskListSnapshotEvent(from: envelope) {
            return [taskListSnapshotEvent]
        }
        if isNonDurablePlanDelta(event) {
            return []
        }
        if isCodexCollaborationTask(event, envelope: envelope) {
            return []
        }

        switch event.phase {
        case .started:
            return [.subAgentStarted(
                toolUseId: event.id,
                description: event.description ?? "",
                taskType: event.taskType
            )]
        case .progress:
            return [.subAgentProgress(
                toolUseId: event.id,
                description: event.description,
                lastToolName: event.lastToolName,
                toolUses: event.toolUses ?? 0,
                totalTokens: event.totalTokens ?? 0,
                durationMs: event.durationMs ?? 0
            )]
        case .notification where isTerminalTaskStatus(event.status):
            return completedSubAgentEvents(from: event)
        case .notification:
            return [.notification(type: event.status ?? "task", message: event.description)]
        case .completed:
            return completedSubAgentEvents(from: event)
        }
    }

    private func completedSubAgentEvents(from event: AgentCLIKit.AgentTaskEvent) -> [ConversationEvent] {
        var events: [ConversationEvent] = [
            .subAgentCompleted(
                toolUseId: event.id,
                status: event.status ?? "completed",
                toolUses: event.toolUses ?? 0,
                totalTokens: event.totalTokens ?? 0,
                durationMs: event.durationMs ?? 0
            )
        ]
        if let output = taskResultOutput(from: event) {
            let resultMetadata = terminalTaskResultMetadata(status: event.status)
            events.append(.toolResult(
                id: event.id,
                output: output,
                isError: isFailedTaskStatus(event.status),
                parentToolUseId: nil,
                metadata: resultMetadata
            ))
        }
        return events
    }

    private func isTerminalTaskStatus(_ status: String?) -> Bool {
        switch normalizedTaskStatus(status) {
        case "completed", "success", "succeeded", "failed", "error", "cancelled", "canceled", "interrupted":
            return true
        default:
            return false
        }
    }

    func isFailedTaskStatus(_ status: String?) -> Bool {
        switch normalizedTaskStatus(status) {
        case "failed", "error":
            return true
        default:
            return false
        }
    }

    func isInterruptedTaskStatus(_ status: String?) -> Bool {
        switch normalizedTaskStatus(status) {
        case "cancelled", "canceled", "interrupted":
            return true
        default:
            return false
        }
    }

    func normalizedTaskStatus(_ status: String?) -> String? {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func terminalTaskResultMetadata(status: String?) -> ToolResultMetadata {
        ToolResultMetadata(
            stderr: nil,
            interrupted: isInterruptedTaskStatus(status),
            isImage: false,
            noOutputExpected: false
        )
    }

    private func taskResultOutput(from event: AgentCLIKit.AgentTaskEvent) -> String? {
        let output = event.metadata.stringValue("result")
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return output
    }

    private func contextCompactionEvents(from event: AgentCLIKit.AgentContextCompactionEvent) -> [ConversationEvent] {
        switch event.phase {
        case .started:
            return [.contextCompactionStarted(id: event.id, trigger: event.trigger)]
        case .completed:
            return [.contextCompactionCompleted(id: event.id, summary: event.summary)]
        case .failed:
            return [.contextCompactionFailed(id: event.id, error: event.errorMessage ?? event.summary)]
        }
    }

    private func interactionEvents(
        from event: AgentCLIKit.AgentInteractionEvent,
        providerSessionId: String?
    ) -> [ConversationEvent] {
        let toolName = event.metadata.stringValue("tool_name") ?? toolName(for: event.kind)
        let toolInput = event.metadata["tool_input"].map(Self.serialized) ?? "{}"
        let approvalIdentityToolInput = event.metadata["approval_identity_tool_input"].map(Self.serialized)
        let request = ToolApprovalRequest(
            sessionId: event.metadata.stringValue("session_id") ?? providerSessionId ?? "",
            toolUseId: event.id.rawValue,
            toolName: toolName,
            toolInput: toolInput,
            approvalIdentityToolInput: approvalIdentityToolInput,
            planMarkdownFallback: event.metadata.stringValue("plan")
        )
        var events: [ConversationEvent] = [.toolApprovalRequested(request)]
        if toolName == "AskUserQuestion" {
            events.append(.toolCall(
                id: event.id.rawValue,
                name: toolName,
                input: toolInput,
                parentToolUseId: event.metadata.stringValue("parent_tool_use_id"),
                callerAgent: event.metadata.stringValue("caller_agent")
            ))
        }
        return events
    }

    private func toolName(for kind: AgentCLIKit.AgentInteractionKind) -> String {
        switch kind {
        case .approval:
            "Tool"
        case .prompt:
            "AskUserQuestion"
        case .planModeExit:
            "ExitPlanMode"
        }
    }

    private func lifecycleEvents(from event: AgentCLIKit.AgentLifecycleEvent) -> [ConversationEvent] {
        switch event.state {
        case .cancelled:
            return [.stop(message: event.message ?? ConversationInterruption.displayMessage)]
        case .failed:
            return [.error(message: event.message ?? "Agent process failed")]
        case .exited:
            return [.stop(message: event.message)]
        case .starting, .running:
            return []
        }
    }

    private func activityEvents(
        from event: AgentCLIKit.AgentActivityEvent,
        envelope: AgentCLIKit.AgentEventEnvelope
    ) -> [ConversationEvent] {
        [
            .runtimeActivity(
                state: activityState(from: event),
                turnId: event.turnId,
                outcome: activityOutcome(from: event, envelope: envelope)
            )
        ]
    }

    private func activityState(from event: AgentCLIKit.AgentActivityEvent) -> ConversationRuntimeActivityState {
        switch event.state {
        case .active:
            return .active
        case .idle:
            return .idle
        }
    }

    private func activityOutcome(
        from event: AgentCLIKit.AgentActivityEvent,
        envelope: AgentCLIKit.AgentEventEnvelope
    ) -> ConversationRuntimeActivityOutcome {
        guard event.state == .idle else {
            return .unknown
        }
        guard envelope.providerId == .codex else {
            return .completed
        }

        if let turnStatus = event.metadata.stringValue("codex_turn_status")?.lowercased() {
            switch turnStatus {
            case "failed":
                return .failed(message: "Codex turn failed.")
            case "cancelled", "canceled", "interrupted":
                return .interrupted
            default:
                break
            }
        }
        if event.metadata.stringValue("codex_status")?.lowercased() == "systemerror" {
            return .failed(message: "Codex App Server reported a thread system error.")
        }
        return .completed
    }

    private func diagnosticEvents(from event: AgentCLIKit.AgentDiagnosticEvent) -> [ConversationEvent] {
        if event.code == .hookApprovalFailed {
            return [.toolApprovalFailed(ToolApprovalFailure(
                sessionId: event.metadata.stringValue("session_id"),
                toolUseId: event.metadata.stringValue("tool_use_id"),
                toolName: event.metadata.stringValue("tool_name"),
                message: event.message
            ))]
        }
        if event.code == .codexAppServerResponseFailure,
           event.severity == .warning,
           event.metadata.stringValue("codex_status")?.lowercased() == "systemerror" {
            return [.error(message: event.message)]
        }
        if event.severity == .error {
            return [.error(message: event.message)]
        }
        guard event.message == "init",
              let sessionId = event.metadata.stringValue("session_id") else {
            return []
        }
        return [.sessionInit(sessionId: sessionId)]
    }

    static func serialized(_ value: AgentCLIKit.JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private extension AgentCLIKitEventMapper {
    func isCodexCollaborationTask(
        _ event: AgentCLIKit.AgentTaskEvent,
        envelope: AgentCLIKit.AgentEventEnvelope
    ) -> Bool {
        envelope.providerId == .codex && event.taskType == "collabAgentToolCall"
    }
}

private extension [String: AgentCLIKit.JSONValue] {
    func stringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else {
            return nil
        }
        return value
    }

    func boolValue(_ key: String) -> Bool? {
        guard case let .bool(value)? = self[key] else {
            return nil
        }
        return value
    }
}
