import Foundation
import Observation

struct QueuedMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let text: String
    let stagedContext: String?
    let requiredPlanModeEnabled: Bool?
    let requiredSpeedMode: AgentSpeedMode?
    /// Provider-facing text for delivery; local UI and transcript must keep using `text`.
    let transportText: String?
    let attachments: [LocalImageAttachment]
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?

    init(
        id: UUID = UUID(),
        text: String,
        stagedContext: String?,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        self.id = id
        self.text = text
        self.stagedContext = stagedContext
        self.requiredPlanModeEnabled = requiredPlanModeEnabled
        self.requiredSpeedMode = requiredSpeedMode
        self.transportText = transportText
        self.attachments = attachments
        self.consumedExitPlanModeRevisionGuidance = consumedExitPlanModeRevisionGuidance
    }
}

@MainActor
@Observable
final class MessageQueue {
    private(set) var pending: [QueuedMessage] = []

    func enqueue(
        _ message: String,
        stagedContext: String? = nil,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        pending.append(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            transportText: transportText,
            attachments: attachments,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
        ))
    }

    func prepend(
        _ message: String,
        stagedContext: String? = nil,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        pending.insert(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            transportText: transportText,
            attachments: attachments,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
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

    func clearExitPlanModeRevisionGuidance() {
        pending = pending.map { message in
            guard message.transportText != nil || message.consumedExitPlanModeRevisionGuidance != nil else {
                return message
            }
            return QueuedMessage(
                id: message.id,
                text: message.text,
                stagedContext: message.stagedContext,
                requiredPlanModeEnabled: nil,
                requiredSpeedMode: message.requiredSpeedMode,
                attachments: message.attachments
            )
        }
    }

    func clear() {
        pending.removeAll()
    }
}
