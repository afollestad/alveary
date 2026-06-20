enum TranscriptNoteKind: Equatable {
    case interrupted
    case sessionHandoff
    case sessionForked
    case enteredPlanMode
    case exitedPlanMode
    case stayingInPlanMode
    case steeredConversation
    case contextCompactionStarted
    case contextCompactionCompleted
    case contextCompactionFailed

    var alignment: TranscriptNoteAlignment {
        switch self {
        case .sessionHandoff, .sessionForked,
             .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return .centered
        case .enteredPlanMode, .exitedPlanMode, .stayingInPlanMode, .steeredConversation:
            return .toolUsageLeading
        case .interrupted:
            return .userBubbleTrailing
        }
    }

    var text: String {
        switch self {
        case .interrupted:
            return "Interrupted"
        case .sessionHandoff:
            return "Session handoff"
        case .sessionForked:
            return ConversationSessionFork.displayMessage
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
