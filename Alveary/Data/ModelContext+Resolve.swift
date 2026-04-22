import Foundation
import SwiftData

extension ModelContext {
    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        resolve(
            FetchDescriptor<AgentThread>(
                predicate: #Predicate { thread in
                    thread.persistentModelID == id
                }
            )
        )
    }

    func resolveProject(id: PersistentIdentifier) -> Project? {
        resolve(
            FetchDescriptor<Project>(
                predicate: #Predicate { project in
                    project.persistentModelID == id
                }
            )
        )
    }

    func resolveConversation(id: PersistentIdentifier) -> Conversation? {
        resolve(
            FetchDescriptor<Conversation>(
                predicate: #Predicate { conversation in
                    conversation.persistentModelID == id
                }
            )
        )
    }

    private func resolve<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Model? {
        try? fetch(descriptor).first
    }
}
