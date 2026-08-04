import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension AgentThreadPullRequestPromptsTests {
    func testUnansweredPromptsAreScopedToTheirConversation() throws {
        let context = ModelContext(try unansweredTestContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestLinkPrompts = [
            unansweredPrompt(number: 7, conversationID: "conversation-1"),
            unansweredPrompt(number: 9, conversationID: "conversation-2")
        ]

        XCTAssertTrue(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-1"))
        XCTAssertTrue(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-2"))
        XCTAssertFalse(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-3"))
        XCTAssertEqual(
            thread.unansweredPullRequestLinkPrompts(conversationID: "conversation-1").map(\.identifier.number),
            [7]
        )
    }

    /// Answered prompts are filtered rather than removed, so a stale entry cannot resurrect a
    /// question — nor light the sidebar dot for one.
    func testLinkedPullRequestStopsCountingAsUnanswered() throws {
        let context = ModelContext(try unansweredTestContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestLinkPrompts = [unansweredPrompt(number: 7, conversationID: "conversation-1")]
        XCTAssertTrue(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-1"))

        thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date())
        ]

        XCTAssertFalse(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-1"))
        XCTAssertEqual(thread.unansweredPullRequestLinkPrompts(conversationID: "conversation-1"), [])
    }

    func testNoStoredPromptsMeansNothingUnanswered() throws {
        let context = ModelContext(try unansweredTestContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)

        XCTAssertNil(thread.pendingPullRequestPromptsJSON)
        XCTAssertFalse(thread.hasUnansweredPullRequestLinkPrompt(conversationID: "conversation-1"))
    }

    func testUnansweredPromptsAreOldestFirst() throws {
        let context = ModelContext(try unansweredTestContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestLinkPrompts = [
            unansweredPrompt(number: 9, conversationID: "conversation-1"),
            unansweredPrompt(number: 7, conversationID: "conversation-1")
        ]

        XCTAssertEqual(
            thread.unansweredPullRequestLinkPrompts(conversationID: "conversation-1").map(\.identifier.number),
            [7, 9]
        )
    }

    private func unansweredIdentifier(number: Int) -> PullRequestIdentifier {
        PullRequestIdentifier(owner: "octo", repo: "alpha", number: number)
    }

    private func unansweredPrompt(number: Int, conversationID: String) -> PendingPullRequestPrompt {
        PendingPullRequestPrompt(
            identifier: unansweredIdentifier(number: number),
            messageEventID: "message-\(number)",
            conversationID: conversationID,
            createdAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func unansweredTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
