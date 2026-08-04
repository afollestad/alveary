import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ConversationDecisionAttentionTests: XCTestCase {
    func testNoSourcesMeansNoDecision() throws {
        let seeded = try seed()

        XCTAssertFalse(ConversationDecisionAttention.none.awaitsDecision(seeded.conversation))
    }

    func testUnresolvedApprovalFlipsIt() throws {
        let seeded = try seed()
        let attention = makeAttention(unresolvedApprovals: [seeded.conversation.id])

        XCTAssertTrue(attention.awaitsDecision(seeded.conversation))
    }

    func testScheduledProposalFlipsIt() throws {
        let seeded = try seed()
        let attention = makeAttention(scheduledProposals: [seeded.conversation.id])

        XCTAssertTrue(attention.awaitsDecision(seeded.conversation))
    }

    func testReviewProposalFlipsIt() throws {
        let seeded = try seed()
        let attention = makeAttention(reviewProposals: [seeded.conversation.id])

        XCTAssertTrue(attention.awaitsDecision(seeded.conversation))
    }

    func testPullRequestLinkPromptFlipsIt() throws {
        let seeded = try seed(withLinkPromptForConversation: true)
        let attention = makeAttention(showsPullRequestLinkPrompts: true)

        XCTAssertTrue(attention.awaitsDecision(seeded.conversation))
    }

    /// Both settings gates live on the caller, so an attention built with prompts off must ignore
    /// a stored question rather than the thread having to know about settings.
    func testPullRequestLinkPromptRespectsTheSettingsGate() throws {
        let seeded = try seed(withLinkPromptForConversation: true)
        let attention = makeAttention(showsPullRequestLinkPrompts: false)

        XCTAssertFalse(attention.awaitsDecision(seeded.conversation))
    }

    func testLinkPromptForAnotherConversationDoesNotFlipIt() throws {
        let seeded = try seed(withLinkPromptForConversation: false)
        let attention = makeAttention(showsPullRequestLinkPrompts: true)

        XCTAssertFalse(attention.awaitsDecision(seeded.conversation))
    }

    /// A fork renders the same widget read-only and owns neither record, so keying both proposal
    /// sources by conversation is what keeps the dot off it.
    func testForkedConversationDoesNotInheritTheProposal() throws {
        let seeded = try seed()
        let fork = Conversation(isMain: false, displayOrder: 1, thread: seeded.thread)
        seeded.context.insert(fork)
        try seeded.context.save()
        let attention = makeAttention(
            scheduledProposals: [seeded.conversation.id],
            reviewProposals: [seeded.conversation.id]
        )

        XCTAssertTrue(attention.awaitsDecision(seeded.conversation))
        XCTAssertFalse(attention.awaitsDecision(fork))
    }

    private struct Seeded {
        let container: ModelContainer
        let context: ModelContext
        let thread: AgentThread
        let conversation: Conversation
    }

    private func makeAttention(
        unresolvedApprovals: Set<String> = [],
        scheduledProposals: Set<String> = [],
        reviewProposals: Set<String> = [],
        showsPullRequestLinkPrompts: Bool = false
    ) -> ConversationDecisionAttention {
        ConversationDecisionAttention(
            unresolvedApprovalConversationIDs: unresolvedApprovals,
            scheduledProposalConversationIDs: scheduledProposals,
            reviewProposalConversationIDs: reviewProposals,
            showsPullRequestLinkPrompts: showsPullRequestLinkPrompts
        )
    }

    private func seed(withLinkPromptForConversation: Bool? = nil) throws -> Seeded {
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
        let thread = AgentThread(name: "Thread", hasCustomName: true)
        context.insert(thread)
        let conversation = Conversation(thread: thread)
        context.insert(conversation)
        if let withLinkPromptForConversation {
            thread.pendingPullRequestLinkPrompts = [
                PendingPullRequestPrompt(
                    identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                    messageEventID: "message-1",
                    conversationID: withLinkPromptForConversation ? conversation.id : "other-conversation",
                    createdAt: Date(timeIntervalSince1970: 1)
                )
            ]
        }
        try context.save()
        return Seeded(container: container, context: context, thread: thread, conversation: conversation)
    }
}
