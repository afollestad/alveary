import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AgentThreadPullRequestLinksTests: XCTestCase {
    func testNewThreadHasNoLinks() {
        let thread = AgentThread(name: "Thread")

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
            LinkedPullRequest(summary: makePullRequestSummary(number: 30), linkedAt: Date(timeIntervalSince1970: 10)),
            LinkedPullRequest(
                summary: makePullRequestSummary(number: 4, status: .merged),
                linkedAt: Date(timeIntervalSince1970: 20)
            )
        ]
        // Preserve insertion order before persistence as well as after reading it back.
        XCTAssertEqual(thread.linkedPullRequests.map(\.id.number), [30, 4])
        try context.save()

        let reread = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertEqual(reread.linkedPullRequests.map(\.id.number), [30, 4])
        XCTAssertEqual(reread.linkedPullRequests.map(\.summary.status), [.open, .merged])
        XCTAssertEqual(reread.linkedPullRequests.map(\.linkedAt), [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 20)
        ])
        XCTAssertTrue(reread.isPullRequestLinked(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 4)))
    }

    /// The payload is a refetchable cache, so a bad blob must read as empty
    /// instead of throwing where the toolbar renders.
    func testMalformedPayloadDecodesToEmpty() {
        let thread = AgentThread(name: "Thread")
        thread.linkedPullRequestsJSON = "{ not json"

        XCTAssertEqual(thread.linkedPullRequests, [])
    }

    func testClearingLinksClearsTheColumn() {
        let thread = AgentThread(name: "Thread")
        thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))
        ]
        XCTAssertNotNil(thread.linkedPullRequestsJSON)

        thread.linkedPullRequests = []

        XCTAssertNil(thread.linkedPullRequestsJSON)
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
