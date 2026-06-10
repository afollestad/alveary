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
