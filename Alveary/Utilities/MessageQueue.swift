import AgentCLIKit
import Foundation
import Observation

struct QueuedMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let text: String
    let stagedContext: String?
    let requiredPlanModeEnabled: Bool?
    let requiredSpeedMode: AgentSpeedMode?
    /// Harness-facing text for delivery; local UI and transcript must keep using `text`.
    let transportText: String?
    let attachments: [LocalImageAttachment]
    let fileAttachments: [LocalFileAttachment]
    let appShots: [AppShotAttachment]
    let harnessMetadata: [String: AgentCLIKit.JSONValue]
    let consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?
    let relayedFrom: RelayedPromptAttribution?

    init(
        id: UUID = UUID(),
        text: String,
        stagedContext: String?,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        harnessMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil,
        relayedFrom: RelayedPromptAttribution? = nil
    ) {
        self.id = id
        self.text = text
        self.stagedContext = stagedContext
        self.requiredPlanModeEnabled = requiredPlanModeEnabled
        self.requiredSpeedMode = requiredSpeedMode
        self.transportText = transportText
        self.attachments = attachments
        self.fileAttachments = fileAttachments
        self.appShots = appShots
        self.harnessMetadata = harnessMetadata
        self.consumedExitPlanModeRevisionGuidance = consumedExitPlanModeRevisionGuidance
        self.relayedFrom = relayedFrom
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
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        harnessMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil,
        relayedFrom: RelayedPromptAttribution? = nil
    ) {
        pending.append(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            transportText: transportText,
            attachments: attachments,
            fileAttachments: fileAttachments,
            appShots: appShots,
            harnessMetadata: harnessMetadata,
            consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance,
            relayedFrom: relayedFrom
        ))
    }

    func prepend(
        _ message: String,
        stagedContext: String? = nil,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        harnessMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil
    ) {
        pending.insert(QueuedMessage(
            text: message,
            stagedContext: stagedContext,
            requiredPlanModeEnabled: requiredPlanModeEnabled,
            requiredSpeedMode: requiredSpeedMode,
            transportText: transportText,
            attachments: attachments,
            fileAttachments: fileAttachments,
            appShots: appShots,
            harnessMetadata: harnessMetadata,
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
            guard message.consumedExitPlanModeRevisionGuidance != nil else {
                return message
            }
            return QueuedMessage(
                id: message.id,
                text: message.text,
                stagedContext: message.stagedContext,
                requiredPlanModeEnabled: nil,
                requiredSpeedMode: message.requiredSpeedMode,
                attachments: message.attachments,
                fileAttachments: message.fileAttachments,
                appShots: message.appShots,
                harnessMetadata: message.harnessMetadata,
                relayedFrom: message.relayedFrom
            )
        }
    }

    func clear() {
        pending.removeAll()
    }
}
