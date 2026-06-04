import Foundation

struct ClaudeContextCompactionState {
    var counter = 0
    var currentId: String?
    var terminalSeen = false
}

extension ClaudeAdapter {
    func decodeSystemInitEvent(_ json: [String: Any]) -> [ConversationEvent] {
        var events: [ConversationEvent] = [.sessionInit(sessionId: json["session_id"] as? String)]
        if let permissionMode = json["permissionMode"] as? String {
            events.append(.permissionModeChanged(permissionMode))
        }
        return events
    }

    func decodeSystemStatusEvent(_ json: [String: Any]) -> [ConversationEvent] {
        var events: [ConversationEvent] = []
        if let permissionMode = json["permissionMode"] as? String {
            events.append(.permissionModeChanged(permissionMode))
        }
        return events
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

    func decodeContextCompactionEvent(_ json: [String: Any]) -> ConversationEvent? {
        let metadata = compactMetadata(json)
        let compactResult = compactStringValue("compact_result", in: json)
            ?? compactStringValue("compactResult", in: json)
            ?? metadata?.compactStringValue("compact_result")
            ?? metadata?.compactStringValue("compactResult")
        let compactError = compactStringValue("compact_error", in: json)
            ?? compactStringValue("compactError", in: json)
            ?? metadata?.compactStringValue("compact_error")
            ?? metadata?.compactStringValue("compactError")
        let phase: ContextCompactionPhase?
        if json["status"] as? String == "compacting" {
            phase = .started
        } else if compactResult == "success" || json["subtype"] as? String == "compact_boundary" {
            phase = .completed
        } else if compactResult == "failed" || compactError != nil {
            phase = .failed
        } else {
            phase = nil
        }
        guard let phase else {
            return nil
        }

        let id = contextCompactionId(phase: phase, sessionId: sessionId(from: json))
        switch phase {
        case .started:
            return .contextCompactionStarted(
                id: id,
                trigger: compactStringValue("trigger", in: json) ?? metadata?.compactStringValue("trigger")
            )
        case .completed:
            return .contextCompactionCompleted(id: id, summary: compactionSummary(from: json, metadata: metadata))
        case .failed:
            return .contextCompactionFailed(id: id, error: compactError ?? compactionSummary(from: json, metadata: metadata))
        }
    }

    private enum ContextCompactionPhase {
        case started
        case completed
        case failed

        var isTerminal: Bool {
            switch self {
            case .started:
                return false
            case .completed, .failed:
                return true
            }
        }
    }

    private func contextCompactionId(phase: ContextCompactionPhase, sessionId: String?) -> String {
        contextCompactionState.withLock { state in
            if phase == .started, state.currentId == nil || state.terminalSeen {
                state.counter += 1
                state.currentId = stableContextCompactionId(sessionId: sessionId, counter: state.counter)
                state.terminalSeen = false
            }
            if phase.isTerminal, state.currentId == nil {
                state.counter += 1
                state.currentId = stableContextCompactionId(sessionId: sessionId, counter: state.counter)
            }
            let id = state.currentId ?? stableContextCompactionId(sessionId: sessionId, counter: state.counter)
            if phase.isTerminal {
                state.terminalSeen = true
            }
            return id
        }
    }

    private func stableContextCompactionId(sessionId: String?, counter: Int) -> String {
        let sessionPart = sessionId?.isEmpty == false ? sessionId ?? "unknown" : "unknown"
        return "claude-context-compaction-\(sessionPart)-\(counter)"
    }

    private func compactMetadata(_ json: [String: Any]) -> [String: Any]? {
        json["compact_metadata"] as? [String: Any] ?? json["compactMetadata"] as? [String: Any]
    }

    private func compactionSummary(from json: [String: Any], metadata: [String: Any]?) -> String? {
        compactStringValue("compact_summary", in: json)
            ?? compactStringValue("compactSummary", in: json)
            ?? compactStringValue("summary", in: json)
            ?? metadata?.compactStringValue("compact_summary")
            ?? metadata?.compactStringValue("compactSummary")
            ?? metadata?.compactStringValue("summary")
    }

    private func compactStringValue(_ key: String, in json: [String: Any]) -> String? {
        guard let value = json[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

private extension [String: Any] {
    func compactStringValue(_ key: String) -> String? {
        guard let value = self[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
