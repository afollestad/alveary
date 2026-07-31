import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class PullRequestLinksViewModelTests: XCTestCase {
    private let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    func testLinkPersistsASnapshotBuiltFromTheValidatingFetch() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .draft)
        )

        await harness.viewModel.link(urlText: "https://github.com/octo/alpha/pull/7", owner: harness.threadOwner)

        let links = harness.thread.linkedPullRequests
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.id, identifier)
        XCTAssertEqual(links.first?.summary.title, "Add caching")
        XCTAssertEqual(links.first?.summary.status, .draft)
        XCTAssertNil(harness.viewModel.linkErrorMessage)
        XCTAssertFalse(harness.viewModel.isLinking)
        XCTAssertEqual(harness.service.detailCallCount, 1)
    }

    /// A project selection links the same way a thread does; the link lands on
    /// the project's own column, not any of its threads.
    func testLinkPersistsOntoAProjectOwner() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .open)
        )

        await harness.viewModel.link(urlText: "https://github.com/octo/alpha/pull/7", owner: harness.projectOwner)

        XCTAssertEqual(harness.project.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.thread.linkedPullRequests, [])
        XCTAssertNil(harness.viewModel.linkErrorMessage)
    }

    /// The create-pull-request flow links an identifier it already holds; no URL
    /// string round trip, same validating fetch.
    func testLinkByIdentifierPersistsASnapshot() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "Add caching", status: .open)
        )

        await harness.viewModel.link(identifier, owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.service.detailCallCount, 1)
    }

    /// A parse failure must not reach the network — the message names the shape
    /// the field expects.
    func testUnparsableInputFailsWithoutFetching() async throws {
        let harness = try Harness()

        await harness.viewModel.link(urlText: "not a pull request", owner: harness.threadOwner)

        XCTAssertEqual(harness.service.detailCallCount, 0)
        XCTAssertEqual(harness.thread.linkedPullRequests, [])
        XCTAssertNotNil(harness.viewModel.linkErrorMessage)
        XCTAssertFalse(harness.viewModel.linkFailureNeedsGitSettings)
    }

    func testFetchFailureLinksNothingAndPublishesTheError() async throws {
        let harness = try Harness()
        harness.service.detailResult = .failure(.requestFailed(statusCode: 404))

        await harness.viewModel.link(urlText: "https://github.com/octo/alpha/pull/7", owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests, [])
        XCTAssertEqual(harness.viewModel.linkErrorMessage, "GitHub request failed with HTTP 404")
        XCTAssertFalse(harness.viewModel.linkFailureNeedsGitSettings)
    }

    /// A missing or signed-out `gh` is fixed in settings, not by retyping, so the
    /// popover needs to know to offer that route.
    func testUnavailableGitHubCLIFlagsTheGitSettingsRoute() async throws {
        let harness = try Harness()
        harness.service.detailResult = .failure(.ghNotInstalled)

        await harness.viewModel.link(urlText: "https://github.com/octo/alpha/pull/7", owner: harness.threadOwner)

        XCTAssertTrue(harness.viewModel.linkFailureNeedsGitSettings)
        XCTAssertEqual(harness.viewModel.linkErrorMessage, "GitHub CLI (gh) is not installed")

        harness.viewModel.clearLinkError()

        XCTAssertNil(harness.viewModel.linkErrorMessage)
        XCTAssertFalse(harness.viewModel.linkFailureNeedsGitSettings)
    }

    func testDuplicateLinkIsRejectedWithoutFetching() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier))
        await harness.viewModel.link(urlText: "https://github.com/octo/alpha/pull/7", owner: harness.threadOwner)
        XCTAssertEqual(harness.service.detailCallCount, 1)

        await harness.viewModel.link(urlText: "octo/alpha#7", owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests.count, 1)
        XCTAssertEqual(harness.service.detailCallCount, 1)
        XCTAssertNotNil(harness.viewModel.linkErrorMessage)
    }

    /// Uniqueness is per owner: the same pull request may be linked from a
    /// thread and its project at once.
    func testSamePullRequestMayLinkFromThreadAndProject() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier))
        await harness.viewModel.link(identifier, owner: harness.threadOwner)

        await harness.viewModel.link(identifier, owner: harness.projectOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests.map(\.id), [identifier])
        XCTAssertEqual(harness.project.linkedPullRequests.map(\.id), [identifier])
        XCTAssertNil(harness.viewModel.linkErrorMessage)
    }

    func testUnlinkRemovesOnlyTheNamedPullRequest() async throws {
        let harness = try Harness()
        harness.thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1)),
            LinkedPullRequest(summary: makePullRequestSummary(number: 9), linkedAt: Date(timeIntervalSince1970: 2))
        ]

        harness.viewModel.unlink(identifier, owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests.map(\.id.number), [9])
    }

    func testUnlinkRemovesFromAProjectOwner() async throws {
        let harness = try Harness()
        harness.project.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7), linkedAt: Date(timeIntervalSince1970: 1))
        ]

        harness.viewModel.unlink(identifier, owner: harness.projectOwner)

        XCTAssertEqual(harness.project.linkedPullRequests, [])
    }

    func testRefreshSnapshotRewritesAStaleStatus() async throws {
        let harness = try Harness()
        harness.thread.linkedPullRequests = [
            LinkedPullRequest(
                summary: makePullRequestSummary(number: 7, title: "Old title", status: .open),
                linkedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        harness.service.detailResult = .success(
            makePullRequestDetail(id: identifier, title: "New title", status: .merged)
        )

        await harness.viewModel.refreshSnapshot(identifier, owner: harness.threadOwner)

        let link = try XCTUnwrap(harness.thread.linkedPullRequests.first)
        XCTAssertEqual(link.summary.status, .merged)
        XCTAssertEqual(link.summary.title, "New title")
        XCTAssertEqual(link.linkedAt, Date(timeIntervalSince1970: 1))
    }

    /// Drives the toolbar glyph following a merge or ready-for-review without a
    /// refetch, using the status the open pane already learned.
    func testApplyStatusRewritesTheStoredSnapshotWithoutFetching() async throws {
        let harness = try Harness()
        harness.thread.linkedPullRequests = [
            LinkedPullRequest(
                summary: makePullRequestSummary(number: 7, status: .draft),
                linkedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        harness.viewModel.applyStatus(.open, to: identifier, owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests.first?.summary.status, .open)
        XCTAssertEqual(harness.service.detailCallCount, 0)
    }

    func testApplyStatusIgnoresUnlinkedPullRequestsAndUnchangedStatuses() async throws {
        let harness = try Harness()
        let linkedAt = Date(timeIntervalSince1970: 1)
        harness.thread.linkedPullRequests = [
            LinkedPullRequest(summary: makePullRequestSummary(number: 7, status: .open), linkedAt: linkedAt)
        ]

        harness.viewModel.applyStatus(.open, to: identifier, owner: harness.threadOwner)
        harness.viewModel.applyStatus(
            .merged,
            to: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 99),
            owner: harness.threadOwner
        )

        XCTAssertEqual(harness.thread.linkedPullRequests.count, 1)
        XCTAssertEqual(harness.thread.linkedPullRequests.first?.summary.status, .open)
    }

    func testRefreshSnapshotLeavesAnUnlinkedPullRequestAlone() async throws {
        let harness = try Harness()
        harness.service.detailResult = .success(makePullRequestDetail(id: identifier, status: .merged))

        await harness.viewModel.refreshSnapshot(identifier, owner: harness.threadOwner)

        XCTAssertEqual(harness.thread.linkedPullRequests, [])
    }

    // MARK: - Detail-to-summary mapping

    /// `PullRequestDetail.updatedAt` is optional; the link time is the honest
    /// stand-in for a summary field the pane never renders as "unknown".
    func testSummaryFallsBackToLinkTimeForAMissingUpdatedAt() {
        var detail = makePullRequestDetail(id: identifier)
        detail = PullRequestDetail(
            id: detail.id,
            title: detail.title,
            url: nil,
            status: detail.status,
            authorLogin: detail.authorLogin,
            authorAvatarURL: nil,
            headRefName: detail.headRefName,
            baseRefName: detail.baseRefName,
            createdAt: nil,
            updatedAt: nil,
            additions: detail.additions,
            deletions: detail.deletions,
            changedFiles: detail.changedFiles,
            bodyMarkdown: detail.bodyMarkdown,
            reviewDecision: nil,
            checks: [],
            comments: [],
            reviews: [],
            reviewThreads: []
        )
        let linkedAt = Date(timeIntervalSince1970: 5_000)

        let summary = PullRequestLinksViewModel.makeSummary(from: detail, linkedAt: linkedAt)

        XCTAssertEqual(summary.updatedAt, linkedAt)
    }

    /// `isAuthored` gates the review footer's Approve / Request changes buttons
    /// until the live detail lands, so an unknown viewer must read as not authored.
    func testAuthorshipDerivesFromTheViewerLogin() {
        var detail = makePullRequestDetail(id: identifier)
        XCTAssertNil(detail.viewerLogin)
        XCTAssertFalse(PullRequestLinksViewModel.makeSummary(from: detail).isAuthored)

        detail.viewerLogin = "bob"
        XCTAssertFalse(PullRequestLinksViewModel.makeSummary(from: detail).isAuthored)

        detail.viewerLogin = detail.authorLogin
        XCTAssertTrue(PullRequestLinksViewModel.makeSummary(from: detail).isAuthored)
    }

    /// Involvement flags are list-search facts with no detail equivalent, and
    /// nothing in the pane reads them.
    func testInvolvementFlagsDefaultToFalse() {
        let summary = PullRequestLinksViewModel.makeSummary(from: makePullRequestDetail(id: identifier))

        XCTAssertFalse(summary.isReviewRequested)
        XCTAssertFalse(summary.hasReviewed)
    }

    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let service: StubPullRequestsService
        let viewModel: PullRequestLinksViewModel
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
            viewModel = PullRequestLinksViewModel(
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
