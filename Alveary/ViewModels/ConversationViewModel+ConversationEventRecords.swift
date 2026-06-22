import Foundation
import SwiftData

extension ConversationViewModel {
    func conversationEventRecords() -> [ConversationEventRecord] {
        let conversationID = conversation.id
        return (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )) ?? []
    }
}
