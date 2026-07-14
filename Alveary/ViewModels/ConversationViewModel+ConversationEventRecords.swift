import Foundation
import SwiftData

extension ConversationViewModel {
    func conversationEventRecords() -> [ConversationEventRecord] {
        let conversationID = conversation.id
        let records = (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )) ?? []

        let scheduledTaskNotes = records.filter {
            $0.type == ConversationEventRecord.scheduledTaskNoteType
        }
        guard !scheduledTaskNotes.isEmpty else {
            return records
        }

        return scheduledTaskNotes + records.filter {
            $0.type != ConversationEventRecord.scheduledTaskNoteType
        }
    }
}
