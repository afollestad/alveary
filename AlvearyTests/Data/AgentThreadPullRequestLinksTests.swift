import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AgentThreadPullRequestLinksTests: XCTestCase {
    func testNewThreadHasNoLinks() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)

        XCTAssertNil(thread.linkedPullRequestsJSON)
        XCTAssertEqual(thread.linkedPullRequests, [])
        XCTAssertFalse(thread.isPullRequestLinked(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)))
    }

    func testLinksSurviveAStoreRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 10)),
            LinkedPullRequest(
                summary: makePullRequestSummary(number: 9, status: .merged),
                linkedAt: Date(timeIntervalSince1970: 20)
            )
        ]
        try context.save()

        let reread = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertEqual(reread.linkedPullRequests.map(\.id.number), [7, 9])
        XCTAssertEqual(reread.linkedPullRequests.map(\.summary.status), [.open, .merged])
        XCTAssertEqual(reread.linkedPullRequests.map(\.linkedAt), [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 20)
        ])
        XCTAssertTrue(reread.isPullRequestLinked(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 9)))
    }

    /// Insertion order is the popover's row order, so it has to be preserved
    /// rather than re-sorted by identifier or date.
    func testLinkOrderIsInsertionOrder() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 30), linkedAt: Date(timeIntervalSince1970: 1)),
            LinkedPullRequest(summary: makePullRequestSummary(number: 4), linkedAt: Date(timeIntervalSince1970: 2))
        ]

        XCTAssertEqual(thread.linkedPullRequests.map(\.id.number), [30, 4])
    }

    /// The payload is a refetchable cache, so a bad blob must read as empty
    /// instead of throwing where the toolbar renders.
    func testMalformedPayloadDecodesToEmpty() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.linkedPullRequestsJSON = "{ not json"

        XCTAssertEqual(thread.linkedPullRequests, [])
    }

    func testClearingLinksClearsTheColumn() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))
        ]
        XCTAssertNotNil(thread.linkedPullRequestsJSON)

        thread.linkedPullRequests = []

        XCTAssertNil(thread.linkedPullRequestsJSON)
    }

    /// A fork gets its own branch, so it gets its own pull requests. The column
    /// is deliberately absent from `AgentThread.init`, which is what enforces it.
    func testForkedThreadDoesNotInheritLinks() throws {
        let context = ModelContext(try makeContainer())
        let source = AgentThread(name: "Source", branch: "feat/change")
        context.insert(source)
        source.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))
        ]

        let fork = AgentThread(name: source.name, branch: "feat/change-fork")
        context.insert(fork)

        XCTAssertEqual(fork.linkedPullRequests, [])
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
