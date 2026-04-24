import Foundation

extension ClaudeAdapter {
    func decodeSystemInitEvent(_ json: [String: Any]) -> [ConversationEvent] {
        var events: [ConversationEvent] = [.sessionInit(sessionId: json["session_id"] as? String)]
        if let permissionMode = json["permissionMode"] as? String {
            events.append(.permissionModeChanged(permissionMode))
        }
        return events
    }

    func decodeSystemStatusEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let permissionMode = json["permissionMode"] as? String else {
            return []
        }
        return [.permissionModeChanged(permissionMode)]
    }

    func decodeTaskStartedEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let toolUseId = requiredString(json["tool_use_id"]) else {
            return malformed("missing tool_use_id in system/task_started")
        }
        return [
            .subAgentStarted(
                toolUseId: toolUseId,
                description: json["description"] as? String ?? "",
                taskType: json["task_type"] as? String
            )
        ]
    }

    func decodeTaskProgressEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let toolUseId = requiredString(json["tool_use_id"]) else {
            return malformed("missing tool_use_id in system/task_progress")
        }
        let usage = json["usage"] as? [String: Any]
        return [
            .subAgentProgress(
                toolUseId: toolUseId,
                description: json["description"] as? String,
                lastToolName: json["last_tool_name"] as? String,
                toolUses: usage?["tool_uses"] as? Int ?? 0,
                totalTokens: usage?["total_tokens"] as? Int ?? 0,
                durationMs: usage?["duration_ms"] as? Int ?? 0
            )
        ]
    }

    func decodeTaskNotificationEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let toolUseId = requiredString(json["tool_use_id"]) else {
            return malformed("missing tool_use_id in system/task_notification")
        }
        let usage = json["usage"] as? [String: Any]
        return [
            .subAgentCompleted(
                toolUseId: toolUseId,
                status: json["status"] as? String ?? "completed",
                toolUses: usage?["tool_uses"] as? Int ?? 0,
                totalTokens: usage?["total_tokens"] as? Int ?? 0,
                durationMs: usage?["duration_ms"] as? Int ?? 0
            )
        ]
    }
}
