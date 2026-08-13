import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class PullRequestLinkServiceTests: XCTestCase {
    private let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    func testLinkPersistsASnapshotBuiltFromTheValidatingFetch() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .draft)
        )

        let outcome = try await harness.linkService.link(identifier, owner: harness.threadOwner)

        guard case .linked(let link) = outcome else {
            return XCTFail("Expected a link, got \(outcome)")
        }
        XCTAssertEqual(link.id, identifier)
        XCTAssertEqual(link.summary.title, "Add caching")
        XCTAssertEqual(link.summary.status, .draft)
        XCTAssertEqual(harness.thread.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.service.detailCallCount, 1)
    }

    func testLinkingTwiceReportsAlreadyLinkedWithoutFetchingAgain() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, title: "Add caching", status: .open))
        _ = try await harness.linkService.link(identifier, owner: harness.threadOwner)

        let outcome = try await harness.linkService.link(identifier, owner: harness.threadOwner)

        guard case .alreadyLinked(let link) = outcome else {
            return XCTFail("Expected alreadyLinked, got \(outcome)")
        }
        XCTAssertEqual(link.id, identifier)
        XCTAssertEqual(harness.thread.linkedPullRequests.count, 1)
        // The duplicate check precedes the fetch, so a repeat costs no network round trip.
        XCTAssertEqual(harness.service.detailCallCount, 1)
    }

    /// Validation and snapshotting are the same call, so an unreachable pull request stores
    /// nothing rather than a snapshot of something that may not exist.
    func testAFetchFailureLinksNothingAndPropagatesTheServiceError() async throws {
        let harness = try Harness()
        harness.service.detailResult = .failure(.requestFailed(statusCode: 404))

        do {
            _ = try await harness.linkService.link(identifier, owner: harness.threadOwner)
            XCTFail("Expected the fetch failure to propagate")
        } catch let error as PullRequestsServiceError {
            XCTAssertEqual(error, .requestFailed(statusCode: 404))
        }

        XCTAssertEqual(harness.thread.linkedPullRequests, [])
    }

    /// The involved-list handover: a summary from a recent search is stored as searched, because
    /// the search already proved the pull request reachable — the only thing the fetch re-proves.
    func testLinkStoresAHandedOverSummaryWithoutFetching() async throws {
        let harness = try Harness()
        let summary = makePullRequestSummary(number: 7, title: "From the search", isReviewRequested: true)

        let outcome = try await harness.linkService.link(identifier, owner: harness.threadOwner, summary: summary)

        guard case .linked(let link) = outcome else {
            return XCTFail("Expected a link, got \(outcome)")
        }
        XCTAssertEqual(link.summary.title, "From the search")
        // Stored as searched, not re-derived: the search's involvement flags are real.
        XCTAssertTrue(link.summary.isReviewRequested)
        XCTAssertEqual(harness.service.detailCallCount, 0)
    }

    /// A summary naming a different pull request is ignored, exactly like a mismatched detail.
    func testAHandedOverSummaryForADifferentPullRequestIsIgnoredAndTheFetchRuns() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, title: "Fetched", status: .open))

        let outcome = try await harness.linkService.link(
            identifier,
            owner: harness.threadOwner,
            summary: makePullRequestSummary(number: 99, title: "Someone else's row")
        )

        guard case .linked(let link) = outcome else {
            return XCTFail("Expected a link, got \(outcome)")
        }
        XCTAssertEqual(link.summary.title, "Fetched")
        XCTAssertEqual(harness.service.detailCallCount, 1)
    }

    /// A caller holding both handed the detail over moments after fetching it, where a search row
    /// may be minutes old — the fresher snapshot wins.
    func testAHandedOverDetailBeatsAHandedOverSummary() async throws {
        let harness = try Harness()

        let outcome = try await harness.linkService.link(
            identifier,
            owner: harness.threadOwner,
            detail: makePullRequestDetail(id: identifier, title: "Fetched by the caller", status: .open),
            summary: makePullRequestSummary(number: 7, title: "From the search")
        )

        guard case .linked(let link) = outcome else {
            return XCTFail("Expected a link, got \(outcome)")
        }
        XCTAssertEqual(link.summary.title, "Fetched by the caller")
        XCTAssertEqual(harness.service.detailCallCount, 0)
    }

    func testLinkingAVanishedOwnerIsSuperseded() async throws {
        let harness = try Harness()
        let missingThread = AgentThread(name: "Detached")

        let outcome = try await harness.linkService.link(
            identifier,
            owner: .thread(missingThread.persistentModelID)
        )

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(harness.service.detailCallCount, 0)
    }

    func testLinkPersistsOntoAProjectOwnerWithoutTouchingItsThreads() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, title: "Add caching", status: .open))

        _ = try await harness.linkService.link(identifier, owner: harness.projectOwner)

        XCTAssertEqual(harness.project.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.thread.linkedPullRequests, [])
    }

    func testUnlinkRemovesTheLocalLinkAndReportsWhatItRemoved() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, title: "Add caching", status: .open))
        _ = try await harness.linkService.link(identifier, owner: harness.threadOwner)

        let outcome = try harness.linkService.unlink(identifier, owner: harness.threadOwner)

        guard case .unlinked(let link) = outcome else {
            return XCTFail("Expected unlinked, got \(outcome)")
        }
        XCTAssertEqual(link.id, identifier)
        XCTAssertEqual(harness.thread.linkedPullRequests, [])
    }

    /// The end state the caller wanted, so it is a success rather than an error.
    func testUnlinkingSomethingNotLinkedReportsNotLinked() throws {
        let harness = try Harness()

        XCTAssertEqual(try harness.linkService.unlink(identifier, owner: harness.threadOwner), .notLinked)
        XCTAssertEqual(harness.thread.linkedPullRequests, [])
    }

    func testUnlinkingAVanishedOwnerReportsOwnerUnavailable() throws {
        let harness = try Harness()
        let missingThread = AgentThread(name: "Detached")

        XCTAssertEqual(
            try harness.linkService.unlink(identifier, owner: .thread(missingThread.persistentModelID)),
            .ownerUnavailable
        )
    }

    /// Unlinking is a local record change; nothing may reach GitHub.
    func testUnlinkNeverCallsGitHub() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, title: "Add caching", status: .open))
        _ = try await harness.linkService.link(identifier, owner: harness.threadOwner)
        let callsAfterLink = harness.service.detailCallCount

        _ = try harness.linkService.unlink(identifier, owner: harness.threadOwner)

        XCTAssertEqual(harness.service.detailCallCount, callsAfterLink)
    }

    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let service: StubPullRequestsService
        let linkService: PullRequestLinkService
        let thread: AgentThread
        let threadOwner: PullRequestLinkOwner
        let project: Project
        let projectOwner: PullRequestLinkOwner

        init() throws {
            container = try ModelContainer(
                for: Project.self,
                AgentThread.self,
                Conversation.self,
                ConversationEventRecord.self,
                ScheduledTask.self,
                ScheduledTaskRun.self,
                ScheduledTaskProposal.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)
            service = StubPullRequestsService()
            linkService = PullRequestLinkService(
                modelContext: context,
                service: service,
                now: { Date(timeIntervalSince1970: 4_242) }
            )
            thread = AgentThread(name: "Thread")
            context.insert(thread)
            project = Project(path: "/tmp/alpha", name: "Alpha")
            context.insert(project)
            try context.save()
            threadOwner = .thread(thread.persistentModelID)
            projectOwner = .project(project.persistentModelID)
        }
    }
}
