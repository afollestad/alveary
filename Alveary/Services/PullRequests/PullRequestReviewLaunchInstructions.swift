import Foundation
import SwiftData

/// Pins a launched single-agent workflow so a later setting change cannot redirect it into its own task.
@MainActor
enum PullRequestReviewLaunchInstructions {
    struct Context {
        let url: URL
        let identifier: PullRequestIdentifier
        let title: String?
    }

    /// Save before dispatch; keeping the snapshot in a hidden event avoids changing the model schema.
    static func store(
        settings: AppSettings,
        pullRequest: Context,
        on conversation: Conversation,
        in modelContext: ModelContext
    ) throws {
        var settings = settings
        settings.pullRequestReviewMode = .singleAgent
        let snapshot = Snapshot(
            identifier: pullRequest.identifier,
            instructions: PullRequestReviewPromptBuilder.reviewInstructions(
                settings: settings, url: pullRequest.url, identifier: pullRequest.identifier, title: pullRequest.title
            )
        )
        guard let content = String(bytes: try JSONEncoder().encode(snapshot), encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        modelContext.insert(ConversationEventRecord(
            type: ConversationEventRecord.pullRequestReviewLaunchInstructionsType,
            content: content, conversation: conversation
        ))
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// A review of a different PR in the same conversation still follows the user's current settings.
    static func instructions(for identifier: PullRequestIdentifier, in conversation: Conversation) throws -> String? {
        let records = conversation.events
            .filter { $0.type == ConversationEventRecord.pullRequestReviewLaunchInstructionsType }
            .sorted { $0.timestamp > $1.timestamp }
        for record in records {
            guard let content = record.content else { throw CocoaError(.coderReadCorrupt) }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(content.utf8))
            if snapshot.identifier.number == identifier.number,
               snapshot.identifier.nameWithOwner.caseInsensitiveCompare(identifier.nameWithOwner) == .orderedSame {
                return snapshot.instructions
            }
        }
        return nil
    }
}

private extension PullRequestReviewLaunchInstructions {
    struct Snapshot: Codable {
        let identifier: PullRequestIdentifier
        let instructions: String
    }
}
