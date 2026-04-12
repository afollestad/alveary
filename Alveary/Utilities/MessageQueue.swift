import Foundation
import Observation

struct QueuedMessage: Identifiable, Sendable, Equatable {
    let id = UUID()
    let text: String
    let stagedContext: String?
}

@MainActor
@Observable
final class MessageQueue {
    private(set) var pending: [QueuedMessage] = []

    func enqueue(_ message: String, stagedContext: String? = nil) {
        pending.append(QueuedMessage(text: message, stagedContext: stagedContext))
    }

    func peekNext() -> QueuedMessage? {
        pending.first
    }

    func dequeueNext() -> QueuedMessage? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    @discardableResult
    func remove(id: UUID) -> QueuedMessage? {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return pending.remove(at: index)
    }

    func clear() {
        pending.removeAll()
    }
}
