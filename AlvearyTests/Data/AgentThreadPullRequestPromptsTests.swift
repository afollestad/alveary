import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AgentThreadPullRequestPromptsTests: XCTestCase {
    func testNewThreadHasNoPromptsOrWatermark() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)

        XCTAssertNil(thread.pendingPullRequestPromptsJSON)
        XCTAssertNil(thread.pullRequestScanWatermark)
        XCTAssertEqual(thread.pendingPullRequestLinkPrompts, [])
        XCTAssertFalse(thread.hasPendingPullRequestPrompt(for: identifier(number: 7)))
    }

    func testPromptsAndWatermarkSurviveAStoreRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestLinkPrompts = [
            makePrompt(number: 7, messageEventID: "message-1"),
            makePrompt(number: 9, messageEventID: "message-2")
        ]
        thread.pullRequestScanWatermark = Date(timeIntervalSince1970: 100)
        try context.save()

        let reread = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertEqual(reread.pendingPullRequestLinkPrompts.map(\.identifier.number), [7, 9])
        XCTAssertEqual(reread.pendingPullRequestLinkPrompts.map(\.messageEventID), ["message-1", "message-2"])
        XCTAssertEqual(reread.pullRequestScanWatermark, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(reread.hasPendingPullRequestPrompt(for: identifier(number: 9)))
    }

    /// The prompt anchors below one bubble, so its id has to distinguish the same
    /// pull request appearing under two different messages.
    func testPromptIDCombinesMessageAndPullRequest() {
        XCTAssertEqual(makePrompt(number: 7, messageEventID: "message-1").id, "message-1|octo/alpha#7")
        XCTAssertNotEqual(
            makePrompt(number: 7, messageEventID: "message-1").id,
            makePrompt(number: 7, messageEventID: "message-2").id
        )
    }

    func testMalformedPayloadDecodesToEmpty() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestPromptsJSON = "{ not json"

        XCTAssertEqual(thread.pendingPullRequestLinkPrompts, [])
    }

    func testClearingPromptsClearsTheColumn() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.pendingPullRequestLinkPrompts = [makePrompt(number: 7, messageEventID: "message-1")]
        XCTAssertNotNil(thread.pendingPullRequestPromptsJSON)

        thread.pendingPullRequestLinkPrompts = []

        XCTAssertNil(thread.pendingPullRequestPromptsJSON)
    }

    /// A fork gets its own history, so it must neither inherit questions about the
    /// source's pull requests nor its scan fence. Both columns are absent from
    /// `AgentThread.init`, which is what enforces it.
    func testForkedThreadInheritsNeitherPromptsNorWatermark() throws {
        let context = ModelContext(try makeContainer())
        let source = AgentThread(name: "Source", branch: "feat/change")
        context.insert(source)
        source.pendingPullRequestLinkPrompts = [makePrompt(number: 7, messageEventID: "message-1")]
        source.pullRequestScanWatermark = Date(timeIntervalSince1970: 100)

        let fork = AgentThread(name: source.name, branch: "feat/change-fork")
        context.insert(fork)

        XCTAssertEqual(fork.pendingPullRequestLinkPrompts, [])
        XCTAssertNil(fork.pullRequestScanWatermark)
    }

    private func identifier(number: Int) -> PullRequestIdentifier {
        PullRequestIdentifier(owner: "octo", repo: "alpha", number: number)
    }

    private func makePrompt(number: Int, messageEventID: String) -> PendingPullRequestPrompt {
        PendingPullRequestPrompt(
            identifier: identifier(number: number),
            messageEventID: messageEventID,
            conversationID: "conversation-1",
            createdAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func makeContainer() throws -> ModelContainer {
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
