import SwiftData

extension ModelContext {
    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        model(for: id) as? AgentThread
    }
}
