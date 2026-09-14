import Foundation

/// Allows retained pipes to outlive a successful worker only when its captured JSONL proves one complete Codex turn.
enum ReviewWorkerCodexCompletion {
    static func canRecover(_ failure: ShellIOFailure) -> Bool {
        let result = failure.result
        guard failure.exitedNormally, result.succeeded, failure.inputCompleted,
              !result.stdoutWasTruncated, !result.stderrWasTruncated,
              failure.stdoutFailure == .drainTimedOut || failure.stderrFailure == .drainTimedOut,
              failure.stdoutFailure == nil || failure.stdoutFailure == .drainTimedOut,
              failure.stderrFailure == nil || failure.stderrFailure == .drainTimedOut,
              result.stdoutData.last == 0x0A,
              let stdout = String(data: result.stdoutData, encoding: .utf8),
              stdout == result.stdout else {
            return false
        }

        return hasCompletedTurn(in: stdout)
    }

    private static func hasCompletedTurn(in stdout: String) -> Bool {
        var state = ReviewWorkerCodexCompletionState()
        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                  state.consume(object) else {
                return false
            }
        }
        return state.completed
    }
}

/// Rejects additional turns or messages that could replace the answer selected by the SDK after completion.
private struct ReviewWorkerCodexCompletionState {
    private(set) var completed = false
    private var started = false
    private var hasMessage = false

    mutating func consume(_ object: [String: Any]) -> Bool {
        guard !completed, let type = object["type"] as? String else { return false }
        switch type {
        case "turn.started":
            guard !started else { return false }
            started = true
        case "turn.completed":
            guard started, hasMessage else { return false }
            completed = true
        case "error", "turn.failed", "agent_message":
            // The SDK also extracts legacy top-level messages; none may replace the proven completed item.
            return false
        case "item.completed":
            return consumeCompletedItem(object["item"])
        default:
            break
        }
        return true
    }

    private mutating func consumeCompletedItem(_ value: Any?) -> Bool {
        guard started, let item = value as? [String: Any], let type = item["type"] as? String else { return false }
        if type == "agent_message" {
            guard let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            hasMessage = true
        }
        return true
    }
}
