import Foundation
import SwiftData

extension ConversationViewModel {
    func conversationEventRecords() -> [ConversationEventRecord] {
        (try? fetchConversationEventRecords()) ?? []
    }

    func rebuildChatItemsFromConversationRecords(
        fallbackEvents: [ConversationEventRecord]? = nil,
        forceFullRebuild: Bool = false
    ) {
        guard let records = ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: fallbackEvents,
            currentProcessedCount: state.grouper.processedCount,
            fetch: fetchConversationEventRecords
        ) else {
            return
        }
        rebuildChatItemsIfNeeded(
            from: records,
            forceFullRebuild: forceFullRebuild
        )
    }

    private func fetchConversationEventRecords() throws -> [ConversationEventRecord] {
        let conversationID = conversation.id
        return try modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )
    }
}

enum ConversationTranscriptRecordRefresh {
    static func resolve(
        fallbackEvents: [ConversationEventRecord]?,
        currentProcessedCount: Int,
        fetch: () throws -> [ConversationEventRecord]
    ) -> [ConversationEventRecord]? {
        // A successful empty fetch is authoritative. Only a thrown fetch may use the
        // view's last query snapshot, and never if it trails the current grouper.
        do {
            return try fetch()
        } catch {
            guard let fallbackEvents, fallbackEvents.count >= currentProcessedCount else {
                return nil
            }
            return fallbackEvents
        }
    }
}
