import Foundation

extension ClaudeAdapter {
    func decodeAttachmentEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let attachment = json["attachment"] as? [String: Any],
              let attachmentType = attachment["type"] as? String else {
            return []
        }

        switch attachmentType {
        case "hook_deferred_tool":
            return hookDeferredToolAttachmentEvent(from: json, attachment: attachment)
        case "hook_non_blocking_error":
            return hookErrorAttachmentEvent(from: json, attachment: attachment)
        default:
            return []
        }
    }

    private func hookDeferredToolAttachmentEvent(
        from json: [String: Any],
        attachment: [String: Any]
    ) -> [ConversationEvent] {
        guard let sessionId = sessionId(from: json),
              let toolUseId = requiredString(attachment["toolUseID"]) ?? requiredString(attachment["tool_use_id"]),
              let toolName = requiredString(attachment["toolName"]) ?? requiredString(attachment["tool_name"]) else {
            return malformed("missing hook_deferred_tool sessionId, toolUseID, or toolName")
        }

        return deferredToolApprovalEvents(
            sessionId: sessionId,
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: serializedToolInput(attachment["toolInput"] ?? attachment["tool_input"]),
            includesSyntheticTokenStop: true
        )
    }

    private func hookErrorAttachmentEvent(
        from json: [String: Any],
        attachment: [String: Any]
    ) -> [ConversationEvent] {
        let hookName = requiredString(attachment["hookName"]) ?? requiredString(attachment["hook_name"]) ?? "unknown hook"
        let toolUseId = requiredString(attachment["toolUseID"]) ?? requiredString(attachment["tool_use_id"])
        let toolName = requiredString(attachment["toolName"])
            ?? requiredString(attachment["tool_name"])
            ?? toolName(fromHookName: hookName)
        let stderr = requiredString(attachment["stderr"])
        let stdout = requiredString(attachment["stdout"])
        let content = requiredString(attachment["content"])
        let detail = stderr ?? stdout ?? content ?? "No hook output was provided."
        let message = "Claude hook failed (\(hookName)): \(detail)"

        return [
            .toolApprovalFailed(
                ToolApprovalFailure(
                    sessionId: sessionId(from: json),
                    toolUseId: toolUseId,
                    toolName: toolName,
                    message: message
                )
            )
        ]
    }

    private func toolName(fromHookName hookName: String) -> String? {
        guard let separator = hookName.firstIndex(of: ":") else {
            return nil
        }
        let name = hookName[hookName.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
