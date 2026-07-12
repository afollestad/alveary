import SwiftData

@MainActor
enum ThreadDetailConversationDeletion {
    static func commit(
        _ conversation: Conversation,
        in modelContext: ModelContext,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        invalidateController: () -> Void
    ) throws {
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
