import Foundation
import SwiftData

/// An unanswered "link this pull request?" question anchored below one transcript
/// message. It persists on the owning thread so the question survives relaunch and
/// full transcript rebuilds; `messageEventID` is the `ConversationEventRecord.id`
/// that is also the message's `ChatItem.id`, which is what anchors the row.
struct PendingPullRequestPrompt: Codable, Equatable, Sendable, Identifiable {
    var identifier: PullRequestIdentifier
    var messageEventID: String
    var conversationID: String
    var createdAt: Date

    var id: String { "\(messageEventID)|\(identifier.displayKey)" }
}

/// The JSON envelope behind `AgentThread.pendingPullRequestPromptsJSON`, mirroring
/// `LinkedPullRequestStorage`: a malformed payload decodes to an empty list rather
/// than throwing, and an empty list encodes to `nil` so the column clears.
enum PendingPullRequestPromptStorage {
    static func decode(_ json: String?) -> [PendingPullRequestPrompt] {
        guard let json,
              let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(PendingPullRequestPromptsEnvelope.self, from: data) else {
            return []
        }
        return envelope.prompts
    }

    static func encode(_ prompts: [PendingPullRequestPrompt]) -> String? {
        guard !prompts.isEmpty else {
            return nil
        }
        let envelope = PendingPullRequestPromptsEnvelope(
            version: PendingPullRequestPromptsEnvelope.currentVersion,
            prompts: prompts
        )
        return (try? JSONEncoder().encode(envelope))
            .flatMap { String(data: $0, encoding: .utf8) }
    }
}

private struct PendingPullRequestPromptsEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let prompts: [PendingPullRequestPrompt]
}

/// Asks the app root to link a detected pull request to a thread. Detection runs on
/// `ConversationViewModel`, but only `PullRequestLinksViewModel` may write links, so
/// the request travels as a notification instead of a direct call.
struct PullRequestLinkRequest {
    let identifier: PullRequestIdentifier
    let threadID: PersistentIdentifier
}

enum PullRequestLinkRequestNotificationKey {
    static let request = "request"
}

extension Notification.Name {
    static let pullRequestLinkRequested = Notification.Name("pullRequestLinkRequested")
}
