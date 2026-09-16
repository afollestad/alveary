import Foundation
import SwiftData

enum ThreadDetailConversationDeletionError: LocalizedError, Equatable {
    case scheduledTaskMainConversationRequired
    case scheduledTaskAttachment

    var errorDescription: String? {
        switch self {
        case .scheduledTaskMainConversationRequired:
            "The original scheduled task conversation is retained with its run history. Delete the Task to remove it."
        case .scheduledTaskAttachment:
            "This thread is attached to a scheduled task. Remove or retarget that schedule first."
        }
    }
}

@MainActor
enum ThreadDetailConversationDeletion {
    static func canRemove(_ conversation: Conversation) -> Bool {
        guard conversation.isMain,
              let thread = conversation.thread else {
            return true
        }
        return thread.scheduledTaskRun == nil &&
            !thread.targetedScheduledTasks.contains { $0.exactTargetConversationID == nil } &&
            !thread.targetedScheduledTaskRuns.contains {
                $0.isExactTargetSnapshot != true && (!$0.hasKnownTerminalStatus || $0.requiresFinalizationRecovery)
            }
    }

    static func requireRemovable(_ conversation: Conversation) throws {
        guard canRemove(conversation) else {
            if conversation.thread?.scheduledTaskRun != nil {
                throw ThreadDetailConversationDeletionError.scheduledTaskMainConversationRequired
            }
            throw ThreadDetailConversationDeletionError.scheduledTaskAttachment
        }
    }

    /// A deletion may offer to stop a callback, but must never commit while it is still finalizing.
    static func requireQuiescent(_ conversation: Conversation) throws {
        guard conversation.thread?.targetedScheduledTaskRuns.contains(where: {
            $0.targetConversationIDSnapshot == conversation.id && (!$0.hasKnownTerminalStatus || $0.requiresFinalizationRecovery)
        }) != true else { throw ThreadDetailConversationDeletionError.scheduledTaskAttachment }
    }

    static func commit(
        _ conversation: Conversation,
        in modelContext: ModelContext,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        invalidateController: () -> Void
    ) throws {
        try requireRemovable(conversation)
        try requireQuiescent(conversation)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let conversationID = conversation.id
        let definitionIDs = ScheduledTaskTargetDetachment.pauseCallbacks(to: conversation)
        modelContext.delete(conversation)
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        NotificationCenter.default.postScheduledTasksDetached(definitionIDs: definitionIDs)
        invalidateController()
        NotificationCenter.default.post(name: .reviewTeamConversationDidDelete, object: nil,
                                        userInfo: ["conversationID": conversationID])
    }
}
