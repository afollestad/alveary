enum TranscriptNoteKind: Equatable {
    case interrupted
    case sessionHandoffInProgress
    case sessionHandoff
    case sessionForked
    case scheduledTask(String)
    /// Names the thread whose agent sent the user row beneath it through `send_prompt_to_thread`.
    case relayedPrompt(threadName: String)
    case enteredPlanMode
    case exitedPlanMode
    case stayingInPlanMode
    case steeredConversation
    case contextCompactionStarted
    case contextCompactionCompleted
    case contextCompactionFailed

    var alignment: TranscriptNoteAlignment {
        switch self {
        case .sessionHandoffInProgress, .sessionHandoff, .sessionForked, .scheduledTask,
             .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return .centered
        case .enteredPlanMode, .exitedPlanMode, .stayingInPlanMode, .steeredConversation:
            return .toolUsageLeading
        case .interrupted, .relayedPrompt:
            return .userBubbleTrailing
        }
    }

    var text: String {
        switch self {
        case .interrupted:
            return "Interrupted"
        case .sessionHandoffInProgress:
            return ConversationSessionHandoff.startedDisplayMessage
        case .sessionHandoff:
            return ConversationSessionHandoff.displayMessage
        case .sessionForked:
            return ConversationSessionFork.displayMessage
        case .scheduledTask(let text):
            return text
        case .relayedPrompt(let threadName):
            return "From thread “\(threadName)”"
        case .enteredPlanMode:
            return "Entered plan mode"
        case .exitedPlanMode:
            return "Exited plan mode"
        case .stayingInPlanMode:
            return "Staying in plan mode"
        case .steeredConversation:
            return ConversationSteering.displayMessage
        case .contextCompactionStarted:
            return ConversationContextCompaction.startedDisplayMessage
        case .contextCompactionCompleted:
            return ConversationContextCompaction.completedDisplayMessage
        case .contextCompactionFailed:
            return ConversationContextCompaction.failedDisplayMessage
        }
    }
}
