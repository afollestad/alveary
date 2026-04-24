import Foundation

final class ClaudeAdapter: AgentAdapter, Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = true
    private let localCommandCaveatStartTag = "<local-command-caveat>"
    private let localCommandCaveatEndTag = "</local-command-caveat>"
    private let hasDeferredTool = LockedState(false)

    func buildArgs(config: AgentConfig) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages"
        ]

        if let permissionMode = config.permissionMode {
            args += ["--permission-mode", permissionMode]
        }
        if let model = config.model {
            args += ["--model", model]
        }
        if let effort = config.effort {
            args += ["--effort", effort]
        }

        return args
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        hasDeferredTool.withLock { hasDeferredTool in
            guard !hasDeferredTool else {
                return []
            }

            let events = decodeEvent(json)
            if events.contains(where: isToolDeferredEvent) {
                hasDeferredTool = true
            }
            return events
        }
    }

    private func decodeEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let type = json["type"] as? String else {
            return []
        }

        let parentToolUseId = json["parent_tool_use_id"] as? String

        switch type {
        case "system":
            return decodeSystemEvent(json)
        case "assistant":
            return decodeAssistantEvent(json, parentToolUseId: parentToolUseId)
        case "user":
            return decodeUserEvent(json, parentToolUseId: parentToolUseId)
        case "stream_event":
            return decodeStreamEvent(json, parentToolUseId: parentToolUseId)
        case "result":
            return decodeResultEvent(json)
        case "attachment":
            return decodeAttachmentEvent(json)
        default:
            return []
        }
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let event: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": message]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw AgentError.spawnFailed("Failed to encode message as UTF-8")
        }

        try stdin.fileHandleForWriting.write(contentsOf: Data((payload + "\n").utf8))
    }

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        let canonicalCwd = CanonicalPath.normalize(cwd)
        let encodedDirectory = ClaudePathEncoding.projectDirectoryName(forCanonicalCwd: canonicalCwd)
        return NSHomeDirectory() + "/.claude/projects/\(encodedDirectory)/\(sessionId).jsonl"
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        guard let path = sessionFilePath(sessionId: sessionId, cwd: cwd) else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        if isResuming, canResumeSession(sessionId: sessionId, cwd: cwd) {
            var args = ["--resume", sessionId]
            if forkSession {
                args.append("--fork-session")
            }
            return SessionLaunchDecision(args: args, continuity: .preserved)
        }

        return SessionLaunchDecision(
            args: ["--session-id", sessionId],
            continuity: isResuming ? .restartedFresh : .preserved
        )
    }

    private func decodeSystemEvent(_ json: [String: Any]) -> [ConversationEvent] {
        guard let subtype = json["subtype"] as? String else {
            return []
        }

        switch subtype {
        case "init":
            return decodeSystemInitEvent(json)
        case "status":
            return decodeSystemStatusEvent(json)
        case "task_started":
            return decodeTaskStartedEvent(json)
        case "task_progress":
            return decodeTaskProgressEvent(json)
        case "task_notification":
            return decodeTaskNotificationEvent(json)
        default:
            return []
        }
    }

    private func decodeAssistantEvent(_ json: [String: Any], parentToolUseId: String?) -> [ConversationEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }

        return content.compactMap { block in
            switch block["type"] as? String {
            case "thinking":
                return .thinking(content: block["thinking"] as? String ?? "", parentToolUseId: parentToolUseId)
            case "text":
                return .message(role: "assistant", content: block["text"] as? String ?? "", parentToolUseId: parentToolUseId)
            case "tool_use":
                guard let toolID = requiredString(block["id"]),
                      let toolName = requiredString(block["name"]) else {
                    return .error(message: "Malformed Claude event: missing tool_use id or name in assistant block")
                }

                let input = (block["input"] as? [String: Any])
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let caller = block["caller"] as? [String: Any]
                let callerAgent = (caller?["type"] as? String == "agent") ? caller?["agent"] as? String : nil

                return .toolCall(
                    id: toolID,
                    name: toolName,
                    input: input,
                    parentToolUseId: parentToolUseId,
                    callerAgent: callerAgent
                )
            default:
                return nil
            }
        }
    }

    private func decodeUserEvent(_ json: [String: Any], parentToolUseId: String?) -> [ConversationEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return []
        }

        let toolUseResult = json["tool_use_result"] as? [String: Any]

        return content.compactMap { block in
            switch block["type"] as? String {
            case "text":
                guard let sanitizedText = sanitizedUserMessageText(block["text"] as? String) else {
                    return nil
                }
                if ConversationInterruption.isRequestInterruptedByUserMarker(sanitizedText.content) {
                    return .stop(message: ConversationInterruption.displayMessage)
                }
                return .message(
                    role: sanitizedText.role,
                    content: sanitizedText.content,
                    parentToolUseId: parentToolUseId
                )
            case "tool_result":
                guard let toolUseId = requiredString(block["tool_use_id"]) else {
                    return .error(message: "Malformed Claude event: missing tool_use_id in tool_result")
                }

                let output = (block["content"] as? String)
                    ?? (toolUseResult?["stdout"] as? String)
                    ?? ""

                let metadata = toolUseResult.map {
                    ToolResultMetadata(
                        stderr: $0["stderr"] as? String,
                        interrupted: $0["interrupted"] as? Bool ?? false,
                        isImage: $0["isImage"] as? Bool ?? false,
                        noOutputExpected: $0["noOutputExpected"] as? Bool ?? false
                    )
                }

                return .toolResult(
                    id: toolUseId,
                    output: output,
                    isError: block["is_error"] as? Bool ?? false,
                    parentToolUseId: parentToolUseId,
                    metadata: metadata
                )
            default:
                return nil
            }
        }
    }

    private func sanitizedUserMessageText(_ rawText: String?) -> (role: String, content: String)? {
        guard let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty else {
            return nil
        }

        var strippedText = trimmedText
        if let startRange = strippedText.range(of: localCommandCaveatStartTag),
           let endRange = strippedText.range(
               of: localCommandCaveatEndTag,
               range: startRange.upperBound..<strippedText.endIndex
           ) {
            strippedText.removeSubrange(endRange)
            strippedText.removeSubrange(startRange)
        }
        strippedText = strippedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !strippedText.isEmpty else {
            return nil
        }

        return (
            role: "assistant",
            content: strippedText
        )
    }

    private func decodeStreamEvent(_ json: [String: Any], parentToolUseId: String?) -> [ConversationEvent] {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String else {
            return []
        }

        guard eventType == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else {
            return []
        }

        return [.messageChunk(text: text, parentToolUseId: parentToolUseId)]
    }

    private func decodeResultEvent(_ json: [String: Any]) -> [ConversationEvent] {
        let usage = json["usage"] as? [String: Any]
        let permissionDenials = (json["permission_denials"] as? [[String: Any]])?.compactMap { entry -> PermissionDenialSummary? in
            guard let toolName = entry["tool_name"] as? String else {
                return nil
            }
            return PermissionDenialSummary(toolName: toolName, toolUseId: entry["tool_use_id"] as? String)
        } ?? []

        var events = deferredToolApprovalEvent(from: json) ?? []
        events.append(
            .tokens(
                input: usage?["input_tokens"] as? Int ?? 0,
                output: usage?["output_tokens"] as? Int ?? 0,
                cacheRead: usage?["cache_read_input_tokens"] as? Int ?? 0,
                isError: json["is_error"] as? Bool ?? false,
                stopReason: json["stop_reason"] as? String,
                durationMs: json["duration_ms"] as? Int ?? 0,
                costUsd: json["total_cost_usd"] as? Double ?? 0,
                permissionDenials: permissionDenials
            )
        )
        return events
    }

    private func deferredToolApprovalEvent(from json: [String: Any]) -> [ConversationEvent]? {
        guard json["stop_reason"] as? String == "tool_deferred",
              let deferredToolUse = json["deferred_tool_use"] as? [String: Any],
              let sessionId = sessionId(from: json),
              let toolUseId = requiredString(deferredToolUse["id"]),
              let toolName = requiredString(deferredToolUse["name"]) else {
            return nil
        }

        return deferredToolApprovalEvents(
            sessionId: sessionId,
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: serializedToolInput(deferredToolUse["input"]),
            includesSyntheticTokenStop: false
        )
    }

    func deferredToolApprovalEvents(
        sessionId: String,
        toolUseId: String,
        toolName: String,
        toolInput: String,
        includesSyntheticTokenStop: Bool
    ) -> [ConversationEvent] {
        var events: [ConversationEvent] = [
            .toolApprovalRequested(
                ToolApprovalRequest(
                    sessionId: sessionId,
                    toolUseId: toolUseId,
                    toolName: toolName,
                    toolInput: toolInput
                )
            )
        ]

        if includesSyntheticTokenStop {
            events.append(
                .tokens(
                    input: 0,
                    output: 0,
                    cacheRead: 0,
                    isError: false,
                    stopReason: "tool_deferred",
                    durationMs: 0,
                    costUsd: 0,
                    permissionDenials: []
                )
            )
        }

        return events
    }

    func sessionId(from json: [String: Any]) -> String? {
        requiredString(json["session_id"]) ?? requiredString(json["sessionId"])
    }

    func serializedToolInput(_ input: Any?) -> String {
        if let input = input as? String, !input.isEmpty {
            return input
        }
        guard let input, JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    func requiredString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    func malformed(_ detail: String) -> [ConversationEvent] {
        [.error(message: "Malformed Claude event: \(detail)")]
    }

    private func isToolDeferredEvent(_ event: ConversationEvent) -> Bool {
        guard case .tokens(_, _, _, _, let stopReason, _, _, _) = event else {
            return false
        }
        return stopReason == "tool_deferred"
    }
}

private extension ClaudeAdapter {
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
