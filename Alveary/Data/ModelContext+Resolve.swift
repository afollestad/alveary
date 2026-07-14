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

    func resolveProject(path: String) -> Project? {
        resolve(
            FetchDescriptor<Project>(
                predicate: #Predicate { project in
                    project.path == path
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

    func resolveConversation(conversationID: String) -> Conversation? {
        resolve(
            FetchDescriptor<Conversation>(
                predicate: #Predicate { conversation in
                    conversation.id == conversationID
                }
            )
        )
    }

    func resolveScheduledTask(id: String) -> ScheduledTask? {
        resolve(
            FetchDescriptor<ScheduledTask>(
                predicate: #Predicate { scheduledTask in
                    scheduledTask.id == id
                }
            )
        )
    }

    func resolveScheduledTask(id: PersistentIdentifier) -> ScheduledTask? {
        resolve(
            FetchDescriptor<ScheduledTask>(
                predicate: #Predicate { scheduledTask in
                    scheduledTask.persistentModelID == id
                }
            )
        )
    }

    func resolveScheduledTaskRun(id: PersistentIdentifier) -> ScheduledTaskRun? {
        resolve(
            FetchDescriptor<ScheduledTaskRun>(
                predicate: #Predicate { run in
                    run.persistentModelID == id
                }
            )
        )
    }

    func resolveScheduledTaskProposal(id: String) -> ScheduledTaskProposal? {
        resolve(
            FetchDescriptor<ScheduledTaskProposal>(
                predicate: #Predicate { proposal in
                    proposal.id == id
                }
            )
        )
    }

    func resolveScheduledTaskProposal(sourceConversationID: String) -> ScheduledTaskProposal? {
        resolve(
            FetchDescriptor<ScheduledTaskProposal>(
                predicate: #Predicate { proposal in
                    proposal.sourceConversationID == sourceConversationID
                }
            )
        )
    }

    func resolveThread(conversationID: String) -> AgentThread? {
        resolveConversation(conversationID: conversationID)?.thread
    }

    private func resolve<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Model? {
        try? fetch(descriptor).first
    }
}
