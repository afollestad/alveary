import Foundation
import SwiftData

enum ThreadDetailConversationDeletionError: LocalizedError, Equatable {
    case scheduledTaskMainConversationRequired

    var errorDescription: String? {
        switch self {
        case .scheduledTaskMainConversationRequired:
            "The original scheduled task conversation is retained with its run history. Delete the Task to remove it."
        }
    }
}

@MainActor
enum ThreadDetailConversationDeletion {
    static func canRemove(_ conversation: Conversation) -> Bool {
        !(conversation.isMain && conversation.thread?.scheduledTaskRun != nil)
    }

    static func requireRemovable(_ conversation: Conversation) throws {
        guard canRemove(conversation) else {
            throw ThreadDetailConversationDeletionError.scheduledTaskMainConversationRequired
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
