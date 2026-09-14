import Observation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class PullRequestLinkedThreadIndexTests: XCTestCase {
    func testDeduplicatesThreadsAndUpdatesAfterUnlinkingAndQueryRemoval() throws {
        let context = ModelContext(try makeContainer())
        let first = AgentThread(name: "First")
        let second = AgentThread(name: "Second")
        context.insert(first)
        context.insert(second)
        let shared = link(number: 7)
        let other = link(number: 8)
        first.linkedPullRequests = [shared]
        second.linkedPullRequests = [shared, other]
        let index = PullRequestLinkedThreadIndex()

        XCTAssertEqual(index.identifiers(in: [first, second]), [shared.id, other.id])

        first.linkedPullRequests = []
        XCTAssertEqual(index.identifiers(in: [first, second]), [shared.id, other.id])

        second.linkedPullRequests = [other]
        XCTAssertEqual(index.identifiers(in: [first, second]), [other.id])
        XCTAssertTrue(index.identifiers(in: [first]).isEmpty)
        XCTAssertEqual(index.identifiers(in: [second]), [other.id])
        XCTAssertTrue(index.identifiers(in: []).isEmpty)
    }

    func testUsesFullPullRequestIdentity() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        let links = [link(number: 7), link(number: 7, owner: "other"), link(number: 7, repo: "beta")]
        thread.linkedPullRequests = links

        XCTAssertEqual(PullRequestLinkedThreadIndex().identifiers(in: [thread]), Set(links.map(\.id)))
    }

    func testArchivedAndDraftRowsDisappearAndRestoreFromStaleQueryResults() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        let linked = link(number: 7)
        thread.linkedPullRequests = [linked]
        let index = PullRequestLinkedThreadIndex()
        XCTAssertEqual(index.identifiers(in: [thread]), [linked.id])

        thread.archivedAt = Date(timeIntervalSince1970: 10)
        XCTAssertTrue(index.identifiers(in: [thread]).isEmpty)
        thread.archivedAt = nil
        XCTAssertEqual(index.identifiers(in: [thread]), [linked.id])

        thread.isDraft = true
        XCTAssertTrue(index.identifiers(in: [thread]).isEmpty)
        thread.isDraft = false
        XCTAssertEqual(index.identifiers(in: [thread]), [linked.id])
    }

    func testDropsPendingAndCommittedDeletesWithoutReadingDeadRows() throws {
        let context = ModelContext(try makeContainer())
        let deleted = AgentThread(name: "Deleted")
        let survivor = AgentThread(name: "Survivor")
        context.insert(deleted)
        context.insert(survivor)
        deleted.linkedPullRequests = [link(number: 7)]
        let remaining = link(number: 8)
        survivor.linkedPullRequests = [remaining]
        try context.save()
        let index = PullRequestLinkedThreadIndex()
        XCTAssertEqual(index.identifiers(in: [deleted, survivor]).count, 2)

        context.delete(deleted)
        XCTAssertEqual(index.identifiers(in: [deleted, survivor]), [remaining.id])
        try context.save()
        XCTAssertEqual(index.identifiers(in: [deleted, survivor]), [remaining.id])
    }

    func testDecodesOnlyChangedPayloadsIncludingMalformedLinks() throws {
        let context = ModelContext(try makeContainer())
        let thread = AgentThread(name: "Thread")
        let broken = AgentThread(name: "Broken")
        context.insert(thread)
        context.insert(broken)
        var linked = link(number: 7)
        thread.linkedPullRequests = [linked]
        broken.linkedPullRequestsJSON = "{ not json"
        var decodeCount = 0
        let index = PullRequestLinkedThreadIndex { json in
            decodeCount += 1
            return LinkedPullRequestStorage.decode(json)
        }
        XCTAssertEqual(index.identifiers(in: [thread, broken]), [linked.id])
        XCTAssertEqual(decodeCount, 2)

        thread.name = "Renamed"
        XCTAssertEqual(index.identifiers(in: [broken, thread]), [linked.id])
        XCTAssertEqual(decodeCount, 2)

        linked.summary.status = .merged
        thread.linkedPullRequests = [linked]
        XCTAssertEqual(index.identifiers(in: [thread, broken]), [linked.id])
        XCTAssertEqual(decodeCount, 3)

        broken.linkedPullRequests = [link(number: 8)]
        XCTAssertEqual(index.identifiers(in: [thread, broken]), [linked.id, link(number: 8).id])
        XCTAssertEqual(decodeCount, 4)
    }

    func testWarmCacheStillObservesLinkAndEligibilityChanges() throws {
        let mutations: [(AgentThread) -> Void] = [
            { $0.linkedPullRequests = [] },
            { $0.archivedAt = Date(timeIntervalSince1970: 10) },
            { $0.isDraft = true }
        ]
        for mutate in mutations {
            let context = ModelContext(try makeContainer())
            let thread = AgentThread(name: "Thread")
            context.insert(thread)
            thread.linkedPullRequests = [link(number: 7)]
            let index = PullRequestLinkedThreadIndex()
            XCTAssertFalse(index.identifiers(in: [thread]).isEmpty)
            let didInvalidate = LockedState(false)

            let identifiers = withObservationTracking {
                index.identifiers(in: [thread])
            } onChange: {
                didInvalidate.withLock { $0 = true }
            }
            XCTAssertFalse(identifiers.isEmpty)
            XCTAssertFalse(didInvalidate.withLock { $0 })

            mutate(thread)

            XCTAssertTrue(didInvalidate.withLock { $0 })
            XCTAssertTrue(index.identifiers(in: [thread]).isEmpty)
        }
    }

    private func link(number: Int, owner: String = "octo", repo: String = "alpha") -> LinkedPullRequest {
        LinkedPullRequest(
            summary: makePullRequestSummary(number: number, repo: "\(owner)/\(repo)"),
            linkedAt: Date(timeIntervalSince1970: 10)
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
