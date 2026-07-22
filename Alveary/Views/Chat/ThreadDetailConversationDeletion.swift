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
            thread.blockingScheduledTaskAttachment == nil &&
            !thread.hasBlockingScheduledTaskRunAttachment
    }

    static func requireRemovable(_ conversation: Conversation) throws {
        guard canRemove(conversation) else {
            if conversation.thread?.scheduledTaskRun != nil {
                throw ThreadDetailConversationDeletionError.scheduledTaskMainConversationRequired
            }
            throw ThreadDetailConversationDeletionError.scheduledTaskAttachment
        }
    }

    static func commit(
        _ conversation: Conversation,
        in modelContext: ModelContext,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        invalidateController: () -> Void
    ) throws {
        try requireRemovable(conversation)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        modelContext.delete(conversation)
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        invalidateController()
    }
}
