import Foundation
import SwiftData

extension ConversationViewModel {
    func appendSessionHandoffStartedNote() {
        guard state.sessionHandoffNoteRecordID == nil,
              let dbConversation = dbConversation(),
              let record = ConversationEvent.stop(message: ConversationSessionHandoff.startedDisplayMessage)
                .toRecord(conversation: dbConversation) else {
            return
        }

        state.sessionHandoffNoteRecordID = record.id
        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }
}

extension ConversationViewModel {
    func completeSessionHandoffNote() {
        if let record = activeSessionHandoffNoteRecord() {
            record.content = ConversationSessionHandoff.completedDisplayMessage
            state.sessionHandoffNoteRecordID = nil
            rebuildChatItemsIfNeeded(from: sessionHandoffConversationEventRecords(), forceFullRebuild: true)
            scheduleSave()
            return
        }

        state.sessionHandoffNoteRecordID = nil
        guard let dbConversation = dbConversation(),
              let record = ConversationEvent.stop(message: ConversationSessionHandoff.displayMessage)
                .toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }

    func removeSessionHandoffStartedNoteIfNeeded() {
        guard let record = activeSessionHandoffNoteRecord(),
              ConversationSessionHandoff.isStartedDisplayMessage(record.content) else {
            state.sessionHandoffNoteRecordID = nil
            return
        }

        modelContext.delete(record)
        state.sessionHandoffNoteRecordID = nil
        rebuildChatItemsIfNeeded(from: sessionHandoffConversationEventRecords(), forceFullRebuild: true)
        scheduleSave()
    }
}

private extension ConversationViewModel {
    func activeSessionHandoffNoteRecord() -> ConversationEventRecord? {
        guard let id = state.sessionHandoffNoteRecordID else {
            return nil
        }

        return try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }

    func sessionHandoffConversationEventRecords() -> [ConversationEventRecord] {
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
