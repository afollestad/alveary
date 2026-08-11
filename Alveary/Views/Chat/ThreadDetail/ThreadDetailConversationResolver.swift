import Foundation
import SwiftData

@MainActor
enum ThreadDetailConversationResolver {
    static func resolve(
        thread: AgentThread,
        selectedConversationID: PersistentIdentifier?,
        modelContext: ModelContext
    ) -> [Conversation] {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        let fetchedConversations = try? modelContext.fetch(descriptor)
        return resolve(
            fetchedConversations: fetchedConversations,
            thread: thread,
            selectedConversationID: selectedConversationID,
            modelContext: modelContext
        )
    }

    /// Treats an empty or failed fetch as transient rather than as "this thread has no
    /// conversations": it falls back to the selected persisted conversation, then to a second live
    /// fetch, before anything downstream may clear the selection. A periodic parent refresh that
    /// took the no-conversation answer at face value would replace a provisional thread with the
    /// empty fallback.
    static func resolve(
        fetchedConversations: [Conversation]?,
        thread: AgentThread,
        selectedConversationID: PersistentIdentifier?,
        modelContext: ModelContext
    ) -> [Conversation] {
        let threadID = thread.persistentModelID
        var resolved = fetchedConversations ?? []

        if resolved.isEmpty,
           let selectedConversationID,
           let selectedConversation = modelContext.resolveConversation(id: selectedConversationID),
           selectedConversation.thread?.persistentModelID == threadID {
            resolved.append(selectedConversation)
        }

        if resolved.isEmpty {
            let allConversations = (try? modelContext.fetch(FetchDescriptor<Conversation>())) ?? []
            resolved = allConversations.filter { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        }

        return resolved.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            if $0.isMain != $1.isMain {
                return $0.isMain && !$1.isMain
            }
            return $0.id < $1.id
        }
    }
}
