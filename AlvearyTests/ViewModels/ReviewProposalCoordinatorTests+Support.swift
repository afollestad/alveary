import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A conversation holding one pending review proposal, plus the coordinator that owns it.
@MainActor
final class ReviewProposalFixture {
    static let proposalID = "proposal-1"
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    let modelContext: ModelContext
    let coordinator: PullRequestReviewProposalCoordinator
    let service = StubPullRequestsService()
    let conversation: Conversation
    let notificationCenter = NotificationCenter()

    init(
        body: String? = "Looks good to me.",
        comments: [PullRequestReviewProposalRecord.Comment]? = nil
    ) throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        modelContext = context
        let thread = AgentThread(name: "Thread")
        let sourceConversation = Conversation(id: "source-conversation", provider: "codex", thread: thread)
        conversation = sourceConversation
        thread.conversations = [sourceConversation]
        context.insert(thread)
        try sourceConversation.storePullRequestReviewProposal(
            PullRequestReviewProposalRecord(
                payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
                id: Self.proposalID,
                deduplicationKey: "dedup-1",
                repositoryNameWithOwner: Self.identifier.nameWithOwner,
                number: Self.identifier.number,
                event: "approve",
                body: body,
                comments: comments,
                titleSnapshot: "Detail title",
                pendingCommentCountSnapshot: 1,
                sourceProviderID: "codex",
                sourceProcessToken: "token",
                sourceRequestID: "request-1",
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        try context.save()

        coordinator = PullRequestReviewProposalCoordinator(
            modelContext: context,
            pullRequestsService: service,
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 2_000) }
        )
    }

    static func stagedComment(
        path: String = "File0.swift",
        line: Int = 1,
        body: String
    ) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(path: path, line: line, side: "RIGHT", body: body)
    }

    func outcomeMarkers() -> [ConversationEventRecord] {
        conversation.events.filter { $0.type == ConversationEventRecord.hostToolOutcomeType }
    }

    /// `confirm` enters the submitting state before its first suspension, but the caller runs it in
    /// its own `Task`; poll with a deadline so a coordinator that never enters it fails the test
    /// rather than spinning the main actor until CI times out.
    func waitForSubmission(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if coordinator.isSubmitting(proposalID: Self.proposalID) {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the submission never started")
    }

    /// The preview loads in its own task; poll rather than guessing at a sleep.
    func waitForPreview(timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch coordinator.preview(forProposalID: Self.proposalID) {
            case .loaded, .failed:
                return
            case .loading, nil:
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        XCTFail("the preview never settled")
    }
}
