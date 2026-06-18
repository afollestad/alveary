import AgentCLIKit
import Foundation

extension AgentCLIKitEventMapper {
    func subAgentEvents(from event: AgentCLIKit.AgentSubAgentEvent) -> [ConversationEvent] {
        switch event.phase {
        case .started:
            return [.toolCall(
                id: event.id,
                name: "Agent",
                input: subAgentToolInput(from: event),
                parentToolUseId: event.parentToolUseId,
                callerAgent: event.callerAgent
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
        case .terminal:
            var events: [ConversationEvent] = [
                .subAgentCompleted(
                    toolUseId: event.id,
                    status: event.status ?? "completed",
                    toolUses: event.toolUses ?? 0,
                    totalTokens: event.totalTokens ?? 0,
                    durationMs: event.durationMs ?? 0
                )
            ]
            if let result = Self.nonEmptyString(event.result) {
                events.append(.toolResult(
                    id: event.id,
                    output: result,
                    isError: isFailedTaskStatus(event.status),
                    parentToolUseId: event.parentToolUseId,
                    metadata: terminalTaskResultMetadata(status: event.status)
                ))
            }
            return events
        }
    }

    private func subAgentToolInput(from event: AgentCLIKit.AgentSubAgentEvent) -> String {
        var input: [String: AgentCLIKit.JSONValue]
        switch event.input {
        case .object(let object):
            input = object
        case let value?:
            input = ["input": value]
        case nil:
            input = [:]
        }

        input["agent_subagent_event"] = .bool(true)
        if input["description"] == nil {
            input["description"] = .string(event.description ?? event.prompt ?? "Agent")
        }
        if let prompt = Self.nonEmptyString(event.prompt), input["prompt"] == nil {
            input["prompt"] = .string(prompt)
        }
        if input["subagent_type"] == nil {
            input["subagent_type"] = .string(event.agentType ?? "general-purpose")
        }
        return Self.serialized(.object(input))
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
