import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    // Tall enough to show the divider and the appended activity timeline —
    // comment cards, review cards, status-event rows, and review threads.
    func testPullRequestPaneOverview() {
        assertMacSnapshot(
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            ),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview"
        )
    }

    func testPullRequestPaneOverviewDark() {
        assertMacSnapshot(
            PullRequestPaneOverview(
                session: PullRequestPaneSnapshots.loadedSession,
                viewModel: PullRequestPaneSnapshots.inertViewModel,
                onOpenFiles: {}
            ),
            size: CGSize(width: 460, height: 1_400),
            named: "pull_request_pane_overview_dark",
            colorScheme: .dark
        )
    }

    func testPullRequestPaneFiles() async throws {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture()
        let session = try XCTUnwrap(fixture.viewModel.paneSessions[fixture.target])

        assertMacSnapshot(
            PullRequestPaneFiles(session: session, viewModel: fixture.viewModel),
            size: CGSize(width: 460, height: 720),
            named: "pull_request_pane_files"
        )
    }

    func testPullRequestPaneLoading() {
        let fixture = PullRequestPaneSnapshots.makeLoadingFixture()

        assertMacSnapshot(
            fixture.pane,
            size: CGSize(width: 460, height: 500),
            named: "pull_request_pane_loading"
        )
    }
}

@MainActor
enum PullRequestPaneSnapshots {
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alveary", number: 41)

    /// A view model that never loads; standalone tab snapshots only need the
    /// avatar loader (letter placeholders for nil URLs) and toggle callbacks.
    static var inertViewModel: PullRequestsViewModel {
        makePullRequestsViewModel(service: StubPullRequestsService())
    }

    static var loadedSession: PullRequestPaneSession {
        var session = PullRequestPaneSession(generation: UUID(), summary: summary)
        session.detail = detail
        session.isLoadingDetail = false
        session.diffFiles = DiffParser.parse(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3))
        session.diffState = .loaded
        return session
    }

    static let summary = makePullRequestSummary(
        number: 41,
        repo: "octo/alveary",
        title: "Add pull request browsing to the sidebar",
        author: "afollestad",
        branch: "af/pull-requests",
        updatedAt: Date(timeIntervalSince1970: 1_799_990_000)
    )

    static let detail = PullRequestDetail(
        id: identifier,
        title: "Add pull request browsing to the sidebar",
        url: nil,
        status: .open,
        authorLogin: "afollestad",
        authorAvatarURL: nil,
        headRefName: "af/pull-requests",
        baseRefName: "main",
        createdAt: Date(timeIntervalSince1970: 1_799_900_000),
        updatedAt: Date(timeIntervalSince1970: 1_799_990_000),
        additions: 482,
        deletions: 37,
        changedFiles: 12,
        bodyMarkdown: "## Summary\nAdds a **Pull requests** sidebar item with filter tabs and a detail pane.\n\n"
            + "- Batched GraphQL listing\n- Review submission",
        reviewDecision: "REVIEW_REQUIRED",
        checks: [
            PullRequestCheck(name: "build", state: .passing, detailsURL: URL(string: "https://ci.example.com/build")),
            PullRequestCheck(name: "test", state: .pending, detailsURL: nil),
            PullRequestCheck(name: "ci/lint", state: .failing, detailsURL: URL(string: "https://ci.example.com/lint"))
        ],
        comments: [
            PullRequestComment(
                authorLogin: "codex-connector",
                authorAvatarURL: nil,
                bodyMarkdown: "Looks promising — one question about the throttle.",
                createdAt: Date(timeIntervalSince1970: 1_799_950_000),
                nodeID: "IC_1",
                reactions: [
                    PullRequestCommentReaction(content: .thumbsUp, count: 2, viewerHasReacted: false)
                ],
                isBot: true
            )
        ],
        reviews: [
            PullRequestReview(
                authorLogin: "miguel",
                authorAvatarURL: nil,
                state: .approved,
                bodyMarkdown: "Ship it.",
                submittedAt: Date(timeIntervalSince1970: 1_799_960_000),
                nodeID: "PRR_1",
                reactions: [
                    PullRequestCommentReaction(content: .hooray, count: 1, viewerHasReacted: true)
                ]
            ),
            PullRequestReview(
                authorLogin: "priya",
                authorAvatarURL: nil,
                state: .changesRequested,
                bodyMarkdown: "",
                submittedAt: Date(timeIntervalSince1970: 1_799_970_000)
            )
        ],
        reviewThreads: [
            PullRequestReviewThread(
                path: "Alveary/Services/Git/PullRequestsService.swift",
                line: 42,
                side: .right,
                isResolved: false,
                isOutdated: true,
                comments: [
                    PullRequestComment(
                        authorLogin: "priya",
                        authorAvatarURL: nil,
                        bodyMarkdown: "Consider clamping this before the fetch.",
                        createdAt: Date(timeIntervalSince1970: 1_799_965_000),
                        databaseId: 987,
                        nodeID: "PRRC_1"
                    )
                ],
                nodeID: "PRT_1"
            )
        ],
        timelineEvents: [
            PullRequestTimelineEvent(
                kind: .convertToDraft,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_940_000)
            ),
            PullRequestTimelineEvent(
                kind: .commit,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_945_000),
                detail: "abc1234 Wire up the sidebar row"
            ),
            PullRequestTimelineEvent(
                kind: .reviewRequested,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_952_000),
                detail: "priya"
            ),
            PullRequestTimelineEvent(
                kind: .readyForReview,
                actorLogin: "afollestad",
                actorAvatarURL: nil,
                createdAt: Date(timeIntervalSince1970: 1_799_955_000)
            )
        ],
        reviewers: [
            PullRequestReviewer(login: "copilot", avatarURL: nil, isBot: true, state: .requested, canReRequest: false),
            PullRequestReviewer(login: "miguel", avatarURL: nil, isBot: false, state: .approved, canReRequest: true),
            PullRequestReviewer(login: "priya", avatarURL: nil, isBot: false, state: .changesRequested, canReRequest: true)
        ],
        nodeID: "PR_41",
        reactions: [
            PullRequestCommentReaction(content: .rocket, count: 3, viewerHasReacted: true)
        ]
    )

    @MainActor
    struct Fixture {
        let viewModel: PullRequestsViewModel
        let target: PullRequestPaneTarget

        var pane: PullRequestPane {
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: {})
        }
    }

    static func makeLoadedFixture() async -> Fixture {
        let service = StubPullRequestsService()
        service.detailResult = .success(detail)
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2, addedLinesPerFile: 3))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        let target = PullRequestPaneTarget.details(identifier)
        for _ in 0..<2_000 {
            if let session = viewModel.paneSessions[target],
               !session.isLoadingDetail,
               session.diffState != .loading {
                break
            }
            await Task.yield()
        }
        return Fixture(viewModel: viewModel, target: target)
    }

    static func makeLoadingFixture() -> Fixture {
        let service = StubPullRequestsService()
        // Never-opened gates keep both loads in flight so the pane renders loading states.
        service.detailGate = PullRequestsServiceGate()
        service.diffGate = PullRequestsServiceGate()
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        return Fixture(viewModel: viewModel, target: .details(identifier))
    }
}
