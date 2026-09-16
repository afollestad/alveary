import Foundation

/// Allows retained pipes to outlive a successful worker only when its captured JSONL proves one complete Codex turn.
enum ReviewWorkerCodexCompletion {
    enum Assessment: Sendable, Equatable {
        case recoverable
        /// Record numbers count nonblank JSONL records, starting at one; no captured content enters diagnostics.
        case rejected(RejectionReason, recordNumber: Int? = nil)

        var diagnostic: String? {
            guard case .rejected(let reason, let recordNumber) = self else { return nil }
            let location = recordNumber.map { " at record \($0)" } ?? ""
            return "Codex completion could not be verified: \(reason.rawValue)\(location)."
        }
    }

    enum RejectionReason: String, Sendable {
        case unsuccessfulExit = "process did not exit successfully"
        case incompleteInput = "standard input was incomplete"
        case truncatedOutput = "captured output was truncated"
        case ineligibleIOFailure = "I/O failure was not solely a drain timeout"
        case missingFinalNewline = "stdout did not end with a newline"
        case invalidUTF8 = "stdout was not valid UTF-8"
        case inconsistentCapture = "stdout bytes did not match the captured text"
        case invalidEvent = "invalid JSON event or missing event type"
        case invalidTurnSequence = "missing or repeated turn start"
        case failedTurn = "an error or failed turn was reported"
        case legacyMessage = "a legacy message could replace the completed answer"
        case invalidItem = "invalid completed item"
        case missingFinalAnswer = "missing or empty final answer"
        case missingCompletion = "missing turn completion"
        case eventsAfterCompletion = "unexpected event after turn completion"
    }

    static func assess(_ failure: ShellIOFailure) -> Assessment {
        let result = failure.result
        guard failure.exitedNormally, result.succeeded else { return .rejected(.unsuccessfulExit) }
        guard failure.inputCompleted else { return .rejected(.incompleteInput) }
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else { return .rejected(.truncatedOutput) }
        guard failure.stdoutFailure == .drainTimedOut || failure.stderrFailure == .drainTimedOut,
              failure.stdoutFailure == nil || failure.stdoutFailure == .drainTimedOut,
              failure.stderrFailure == nil || failure.stderrFailure == .drainTimedOut else {
            return .rejected(.ineligibleIOFailure)
        }
        guard result.stdoutData.last == 0x0A else { return .rejected(.missingFinalNewline) }
        guard let stdout = String(data: result.stdoutData, encoding: .utf8) else { return .rejected(.invalidUTF8) }
        guard stdout == result.stdout else { return .rejected(.inconsistentCapture) }

        return assessTurn(in: stdout)
    }

    private static func assessTurn(in stdout: String) -> Assessment {
        var state = ReviewWorkerCodexCompletionState()
        var recordNumber = 0
        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            recordNumber += 1
            guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
                return .rejected(.invalidEvent, recordNumber: recordNumber)
            }
            if let reason = state.consume(object) {
                return .rejected(reason, recordNumber: recordNumber)
            }
        }
        return state.completed ? .recoverable : .rejected(.missingCompletion)
    }
}

/// Rejects additional turns or messages that could replace the answer selected by the SDK after completion.
private struct ReviewWorkerCodexCompletionState {
    private(set) var completed = false
    private var started = false
    private var hasMessage = false

    mutating func consume(_ object: [String: Any]) -> ReviewWorkerCodexCompletion.RejectionReason? {
        guard !completed else { return .eventsAfterCompletion }
        guard let type = object["type"] as? String else { return .invalidEvent }
        switch type {
        case "turn.started":
            guard !started else { return .invalidTurnSequence }
            started = true
        case "turn.completed":
            return completeTurn()
        case "error", "turn.failed":
            return .failedTurn
        case "agent_message":
            // The SDK also extracts legacy top-level messages; none may replace the proven completed item.
            return .legacyMessage
        case "item.completed":
            return consumeCompletedItem(object["item"])
        default:
            break
        }
        return nil
    }

    private mutating func completeTurn() -> ReviewWorkerCodexCompletion.RejectionReason? {
        guard started else { return .invalidTurnSequence }
        guard hasMessage else { return .missingFinalAnswer }
        completed = true
        return nil
    }

    private mutating func consumeCompletedItem(_ value: Any?) -> ReviewWorkerCodexCompletion.RejectionReason? {
        guard started else { return .invalidTurnSequence }
        guard let item = value as? [String: Any], let type = item["type"] as? String else { return .invalidItem }
        if type == "agent_message" {
            guard let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .missingFinalAnswer
            }
            hasMessage = true
        }
        return nil
    }
}
