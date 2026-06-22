struct LocalUserMessageAttemptMetadata {
    let restoresConversationTitle: Bool
    let conversationTitle: String?
}

struct LocalUserMessageAttempt {
    let id: String
    let stagedContext: String?
    let transportText: String?
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?
    let insertedMessage: Bool
    let metadata: LocalUserMessageAttemptMetadata?
}

enum LocalUserMessageFailureHandling {
    case retryable
    case removeAttempt
}
