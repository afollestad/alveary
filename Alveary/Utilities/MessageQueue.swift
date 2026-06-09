import Foundation
import Observation

struct QueuedMessage: Identifiable, Sendable, Equatable {
    let id = UUID()
    let text: String
    let stagedContext: String?
    let requiredPlanModeEnabled: Bool?

    init(text: String, stagedContext: String?, requiredPlanModeEnabled: Bool? = nil) {
        self.text = text
        self.stagedContext = stagedContext
        self.requiredPlanModeEnabled = requiredPlanModeEnabled
    }
}

@MainActor
@Observable
final class MessageQueue {
    private(set) var pending: [QueuedMessage] = []

    func enqueue(_ message: String, stagedContext: String? = nil, requiredPlanModeEnabled: Bool? = nil) {
        pending.append(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled
        ))
    }

    func prepend(_ message: String, stagedContext: String? = nil, requiredPlanModeEnabled: Bool? = nil) {
        pending.insert(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled
        ), at: 0)
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
