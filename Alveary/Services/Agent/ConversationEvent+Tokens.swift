import Foundation

struct TokenEventPayload {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheCreation: Int
    let isError: Bool
    let stopReason: String?
    let contextWindowSize: Int?
    let permissionDenials: [PermissionDenialSummary]
    let isTerminal: Bool

    init(
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheCreation: Int,
        isError: Bool,
        stopReason: String?,
        contextWindowSize: Int? = nil,
        permissionDenials: [PermissionDenialSummary],
        isTerminal: Bool = false
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.isError = isError
        self.stopReason = stopReason
        self.contextWindowSize = contextWindowSize
        self.permissionDenials = permissionDenials
        self.isTerminal = isTerminal
    }

    init?(_ event: ConversationEvent) {
        guard case let .tokens(
            input,
            output,
            cacheRead,
            cacheCreation,
            isError,
            stopReason,
            _,
            _,
            _,
            contextWindowSize,
            permissionDenials,
            isTerminal
        ) = event else {
            return nil
        }

        self.init(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheCreation: cacheCreation,
            isError: isError,
            stopReason: stopReason,
            contextWindowSize: contextWindowSize,
            permissionDenials: permissionDenials,
            isTerminal: isTerminal
        )
    }

    var completesTurn: Bool {
        if isError || !permissionDenials.isEmpty {
            return true
        }
        switch stopReason {
        case ConversationEvent.interimUsageStopReason, "tool_use", "tool_deferred":
            return false
        default:
            return isTerminal || stopReason != nil
        }
    }
}

enum ConversationErrorDisplayPolicy {
    static let genericAgentTurnFailureMessage = "Agent turn failed"
    static let genericPreviousRunFailureMessage = "The previous run ended with an error."
    static let genericNotificationFailureMessage = "Your agent encountered an error"
    static let genericSessionHandoffFailureMessage = "Session handoff failed."

    static func messagesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedText(lhs),
              let rhs = normalizedText(rhs) else {
            return false
        }
        return lhs == rhs
    }

    static func isGenericStopReason(_ stopReason: String?) -> Bool {
        guard let normalized = normalizedText(stopReason) else {
            return true
        }
        return genericStopReasons.contains(normalized)
    }

    static func tokenErrorMessage(stopReason: String?, fallback: String = genericAgentTurnFailureMessage) -> String {
        guard !isGenericStopReason(stopReason),
              let displayText = collapsedDisplayText(stopReason) else {
            return fallback
        }
        return displayText
    }

    static func notificationErrorMessage(stopReason: String?) -> String {
        tokenErrorMessage(stopReason: stopReason, fallback: genericNotificationFailureMessage)
    }

    static func restoreErrorTokenMessage(stopReason: String?) -> String {
        tokenErrorMessage(stopReason: stopReason, fallback: genericPreviousRunFailureMessage)
    }

    static func sessionHandoffTokenFailureMessage(stopReason: String?) -> String {
        tokenErrorMessage(stopReason: stopReason, fallback: genericSessionHandoffFailureMessage)
    }

    static func normalizedText(_ text: String?) -> String? {
        collapsedDisplayText(text)?.lowercased()
    }

    private static func collapsedDisplayText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

private let genericStopReasons: Set<String> = [
    ConversationEvent.interimUsageStopReason,
    "end_turn",
    "max_tokens",
    "pause_turn",
    "refusal",
    "stop_sequence",
    "tool_deferred",
    "tool_use"
]
