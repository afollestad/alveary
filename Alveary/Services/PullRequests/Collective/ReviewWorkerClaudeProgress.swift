import Foundation

/// How far a Claude review worker got before its timeout, read from the `stream-json` events it had written, so the failure
/// says whether it was stuck on the API or still working. Counts and retry categories only: the stream holds review content
/// and reasoning, which never enters a persisted failure.
struct ReviewWorkerClaudeProgress {
    private struct Retry {
        let attempt: Int?
        let maximum: Int?
        let category: String?
        let status: Int?
    }

    /// The capture stopped at the output limit, so the counts cover only the start and the final state is unknown.
    private let isPartial: Bool
    /// Each content block arrives as its own event, and a turn's blocks share one message ID.
    private var messageIDs = Set<String>()
    /// Turns the model's safeguards stopped, which Claude Code continues past once, so they cost time without failing.
    private var refusedMessageIDs = Set<String>()
    private var toolCalls = 0
    /// Prompt-side tokens of the newest answered request, which is the whole conversation up to it.
    private var contextTokens: Int?
    /// Tool output that arrived after `contextTokens` was measured, which a request still in flight carries on top of it.
    private var resultBytesSinceUsage = 0
    private var retryCount = 0
    private var lastRetry: Retry?
    /// Nothing arrived after the newest retry, so the worker was waiting on the API when it was stopped.
    private var stoppedWhileRetrying = false

    /// Nil when the capture holds no events. A line cut off by the kill or the limit fails to parse and is skipped.
    init?(stdout: Data, wasTruncated: Bool) {
        isPartial = wasTruncated
        var sawEvent = false
        for line in stdout.split(separator: UInt8(ascii: "\n")) {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            sawEvent = true
            switch type {
            case "assistant":
                consumeAssistant(event["message"] as? [String: Any] ?? [:])
            case "user":
                stoppedWhileRetrying = false
                resultBytesSinceUsage += Self.resultBytes(event["message"] as? [String: Any] ?? [:])
            case "system" where event["subtype"] as? String == "api_retry":
                consumeRetry(event)
            default:
                break
            }
        }
        guard sawEvent else { return nil }
    }

    var summary: String {
        let turnCount = ReviewTeamDiagnostics.counted(messageIDs.count, "turn")
        let toolCount = ReviewTeamDiagnostics.counted(toolCalls, "tool call")
        let lead = isPartial ? "Its output passed the capture limit, so this covers only its start. It had taken" : "It had taken"
        var text = "\(lead) \(turnCount) and made \(toolCount)"
        if let contextTokens {
            text += ", and its last answered request carried \(Self.tokens(contextTokens)) of context"
            if resultBytesSinceUsage > 0 { text += ", with \(Self.size(resultBytesSinceUsage)) of tool output read since" }
        }
        text += "."
        if !refusedMessageIDs.isEmpty {
            text += " The model's safeguards stopped \(refusedMessageIDs.count) of its responses."
        }
        guard let lastRetry else { return text }
        let detail = Self.detail(lastRetry)
        if stoppedWhileRetrying, !isPartial {
            text += " It was retrying a failed API request when it was stopped"
            text += detail.isEmpty ? "." : " (\(detail))."
        } else {
            text += " It had retried failed API requests \(ReviewTeamDiagnostics.counted(retryCount, "time"))"
            text += detail.isEmpty ? "." : " (last: \(detail))."
        }
        return text
    }

    private mutating func consumeAssistant(_ message: [String: Any]) {
        stoppedWhileRetrying = false
        if let id = message["id"] as? String {
            // A new message is a new request, which carried every tool result read before it.
            if messageIDs.insert(id).inserted { resultBytesSinceUsage = 0 }
            if message["stop_reason"] as? String == "refusal" { refusedMessageIDs.insert(id) }
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        toolCalls += blocks.filter { $0["type"] as? String == "tool_use" }.count
        if let usage = message["usage"] as? [String: Any] {
            let keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            contextTokens = keys.reduce(0) { (total: Int, key: String) -> Int in total + (usage[key] as? Int ?? 0) }
        }
    }

    private mutating func consumeRetry(_ event: [String: Any]) {
        retryCount += 1
        stoppedWhileRetrying = true
        lastRetry = Retry(
            attempt: event["attempt"] as? Int,
            maximum: event["max_retries"] as? Int,
            category: Self.category(event["error"] as? String),
            status: event["error_status"] as? Int
        )
    }

    private static func resultBytes(_ message: [String: Any]) -> Int {
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.reduce(0) { (total: Int, block: [String: Any]) -> Int in
            switch block["content"] {
            case let text as String:
                total + text.utf8.count
            case let parts as [[String: Any]]:
                total + parts.reduce(0) { (sum: Int, part: [String: Any]) -> Int in sum + ((part["text"] as? String)?.utf8.count ?? 0) }
            default:
                total
            }
        }
    }

    /// Claude reports a short category such as `rate_limit`; anything else could be message text, so it is dropped.
    private static func category(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 40,
              value.allSatisfy({ $0 == "_" || ($0.isASCII && ($0.isLowercase || $0.isNumber)) }) else { return nil }
        return value
    }

    private static func detail(_ retry: Retry) -> String {
        var parts: [String] = []
        if let attempt = retry.attempt {
            parts.append(retry.maximum.map { "attempt \(attempt) of \($0)" } ?? "attempt \(attempt)")
        }
        if let category = retry.category { parts.append(category) }
        if let status = retry.status { parts.append("HTTP \(status)") }
        return parts.joined(separator: ", ")
    }

    private static func tokens(_ count: Int) -> String {
        count >= 1_000 ? "\(count / 1_000)K tokens" : ReviewTeamDiagnostics.counted(count, "token")
    }

    private static func size(_ bytes: Int) -> String {
        switch bytes {
        case 1_000_000...: String(format: "%.1f MB", Double(bytes) / 1_000_000)
        case 1_000...: "\(bytes / 1_000) KB"
        default: ReviewTeamDiagnostics.counted(bytes, "byte")
        }
    }
}
