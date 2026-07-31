import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// The project column shares `LinkedPullRequestStorage` with the thread column;
/// this covers the project side of the round trip and the shared failure modes.
@MainActor
final class ProjectPullRequestLinksTests: XCTestCase {
    func testNewProjectHasNoLinks() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)

        XCTAssertNil(project.linkedPullRequestsJSON)
        XCTAssertEqual(project.linkedPullRequests, [])
        XCTAssertFalse(project.isPullRequestLinked(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)))
    }

    func testLinksSurviveAStoreRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        project.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 10)),
            LinkedPullRequest(
                summary: makePullRequestSummary(number: 9, status: .merged),
                linkedAt: Date(timeIntervalSince1970: 20)
            )
        ]
        try context.save()

        let reread = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(reread.linkedPullRequests.map(\.id.number), [7, 9])
        XCTAssertEqual(reread.linkedPullRequests.map(\.summary.status), [.open, .merged])
        XCTAssertTrue(reread.isPullRequestLinked(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 9)))
    }

    func testMalformedPayloadDecodesToEmpty() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        project.linkedPullRequestsJSON = "{ not json"

        XCTAssertEqual(project.linkedPullRequests, [])
    }

    func testClearingLinksClearsTheColumn() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        project.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))
        ]
        XCTAssertNotNil(project.linkedPullRequestsJSON)

        project.linkedPullRequests = []

        XCTAssertNil(project.linkedPullRequestsJSON)
    }

    /// The `ModelContext` owner helpers back `PullRequestLinksViewModel`; both
    /// owner cases resolve, and a deleted owner reads as nil rather than empty.
    func testOwnerHelpersResolveAndWriteBothOwnerKinds() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        let thread = AgentThread(name: "Thread")
        context.insert(project)
        context.insert(thread)
        try context.save()
        let projectOwner = PullRequestLinkOwner.project(project.persistentModelID)
        let threadOwner = PullRequestLinkOwner.thread(thread.persistentModelID)
        let link = LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(context.linkedPullRequests(for: projectOwner), [])
        XCTAssertEqual(context.linkedPullRequests(for: threadOwner), [])
        XCTAssertTrue(context.setLinkedPullRequests([link], for: projectOwner))
        XCTAssertTrue(context.setLinkedPullRequests([link], for: threadOwner))
        XCTAssertEqual(context.linkedPullRequests(for: projectOwner)?.map(\.id.number), [7])
        XCTAssertEqual(context.linkedPullRequests(for: threadOwner)?.map(\.id.number), [7])

        context.delete(project)
        try context.save()

        XCTAssertNil(context.linkedPullRequests(for: projectOwner))
        XCTAssertFalse(context.setLinkedPullRequests([link], for: projectOwner))
    }

    // MARK: - Aggregation

    /// A project surfaces its own links first, then child-thread links ordered
    /// by `linkedAt` across threads, each labeled with its thread.
    func testAggregationListsOwnLinksThenChildThreadLinksByLinkTime() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        project.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 1), linkedAt: Date(timeIntervalSince1970: 50))
        ]
        let earlyThread = AgentThread(name: "Early", project: project)
        let lateThread = AgentThread(name: "Late", project: project)
        context.insert(earlyThread)
        context.insert(lateThread)
        lateThread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 3), linkedAt: Date(timeIntervalSince1970: 20))
        ]
        earlyThread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 2), linkedAt: Date(timeIntervalSince1970: 10))
        ]
        try context.save()

        let rows = project.aggregatedPullRequestLinks

        XCTAssertEqual(rows.map(\.id.number), [1, 2, 3])
        XCTAssertEqual(rows.map(\.sourceLabel), [nil, "Early", "Late"])
        XCTAssertEqual(rows[0].owner, .project(project.persistentModelID))
        XCTAssertEqual(rows[1].owner, .thread(earlyThread.persistentModelID))
        XCTAssertEqual(rows[2].owner, .thread(lateThread.persistentModelID))
    }

    /// The same pull request linked on the project and a child thread renders
    /// once, as the project's own row.
    func testAggregationDeduplicatesWithTheProjectCopyWinning() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        let shared = LinkedPullRequest(
            summary: makePullRequestSummary(number: 7),
            linkedAt: Date(timeIntervalSince1970: 10)
        )
        project.linkedPullRequests = [shared]
        let thread = AgentThread(name: "Thread", project: project)
        context.insert(thread)
        thread.linkedPullRequests = [shared]
        try context.save()

        let rows = project.aggregatedPullRequestLinks

        XCTAssertEqual(rows.map(\.id.number), [7])
        XCTAssertEqual(rows.first?.owner, .project(project.persistentModelID))
        XCTAssertNil(rows.first?.sourceLabel)
    }

    /// Drafts and archived threads are hidden from the sidebar, so their links
    /// stay out of the project's aggregate too.
    func testAggregationExcludesDraftAndArchivedThreads() throws {
        let context = ModelContext(try makeContainer())
        let project = Project(path: "/tmp/alpha", name: "Alpha")
        context.insert(project)
        let draft = AgentThread(name: "Draft", isDraft: true, project: project)
        let archived = AgentThread(name: "Archived", archivedAt: Date(timeIntervalSince1970: 99), project: project)
        let live = AgentThread(name: "Live", project: project)
        context.insert(draft)
        context.insert(archived)
        context.insert(live)
        draft.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 1), linkedAt: Date(timeIntervalSince1970: 1))
        ]
        archived.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 2), linkedAt: Date(timeIntervalSince1970: 2))
        ]
        live.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 3), linkedAt: Date(timeIntervalSince1970: 3))
        ]
        try context.save()

        XCTAssertEqual(project.aggregatedPullRequestLinks.map(\.id.number), [3])
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
