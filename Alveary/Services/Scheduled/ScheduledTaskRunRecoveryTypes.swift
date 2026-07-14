import SwiftData

struct ScheduledTaskRunRecoveryResult: Equatable {
    let resumedRunIDs: [PersistentIdentifier]
    let interruptedRunIDs: [PersistentIdentifier]
}

struct ScheduledTaskTerminationPreparation: Equatable {
    let interruptedRunIDs: [PersistentIdentifier]
    let conversationIDsToTerminate: [String]
    let controllerFlushFailures: [ConversationControllerFlushFailure]
}
