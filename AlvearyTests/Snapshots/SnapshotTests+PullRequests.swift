import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testPullRequestsScreenEmpty() async {
        let fixture = await PullRequestsSnapshotFixture(summaries: [])

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_empty"
        )
    }

    func testPullRequestsScreenPopulated() async {
        let fixture = await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_populated"
        )
    }

    func testPullRequestsScreenPopulatedDark() async {
        let fixture = await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_populated_dark",
            colorScheme: .dark
        )
    }

    func testPullRequestsScreenPopulatedNarrow() async {
        let fixture = await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 620, height: 700),
            named: "pull_requests_populated_narrow"
        )
    }

    func testPullRequestsScreenNoSearchMatches() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.searchQuery = "nothing matches this"

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_no_search_matches"
        )
    }

    func testPullRequestsScreenNotInstalled() async {
        let fixture = await PullRequestsSnapshotFixture(failure: .ghNotInstalled)

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_not_installed"
        )
    }

    func testPullRequestsReviewingSectionsPopulated() async {
        let fixture = await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            PullRequestsSectionedList(
                sections: fixture.viewModel.visibleSections(for: .reviewing),
                showsRepository: true,
                referenceDate: fixture.viewModel.referenceDate,
                avatarLoader: fixture.viewModel.avatarLoader,
                activeDetailID: nil,
                onSelect: { _ in }
            )
            .padding(20),
            size: CGSize(width: 1_120, height: 460),
            named: "pull_requests_reviewing_sections"
        )
    }

    func testPullRequestsFilterChipsReviewingSelection() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 900, height: 72),
            named: "pull_requests_header_reviewing"
        )
    }

    func testPullRequestsScreenPopulatedSqueezed() async {
        let fixture = await PullRequestsSnapshotFixture()

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 420, height: 700),
            named: "pull_requests_populated_squeezed"
        )
    }

    /// Squeezed, the ladder gives up the field's width before the chips: the field
    /// compresses well below its 220 cap while every chip stays visible. 500 sits clear
    /// of the rung boundary (~480), where text measured a point wider on CI's renderer
    /// picked the dropdown instead.
    func testPullRequestsHeaderKeepsChipsBySqueezingTheField() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 500, height: 72),
            named: "pull_requests_header_chips_squeezed_field"
        )
    }

    /// The last rung: chips folded, search field traded for a button. 300 points is
    /// narrower than `RightPaneWidthPolicy.minimumMainPaneWidth`, which the pane really
    /// does reach once the window cannot satisfy both panes' minimums.
    func testPullRequestsHeaderCondensed() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 300, height: 72),
            named: "pull_requests_header_condensed"
        )
    }

    /// A collapsed search reports an active query by tinting its glyph with the accent,
    /// so the state survives losing the field itself.
    func testPullRequestsHeaderCondensedActiveSearch() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)
        fixture.viewModel.searchQuery = "release"

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 300, height: 72),
            named: "pull_requests_header_condensed_active_search"
        )
    }

    /// The dropdown truncates and holds the leading edge instead of being pushed out.
    func testPullRequestsHeaderAtExtremeNarrowWidth() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectFilter(.reviewing)

        assertMacSnapshot(
            PullRequestsScreenHeader(viewModel: fixture.viewModel),
            size: CGSize(width: 220, height: 72),
            named: "pull_requests_header_extreme_narrow"
        )
    }

    // Content-only: live popover hosts crash on macOS 26 (see AlvearyTests/AGENTS.md).
    func testPullRequestsFilterPopoverContent() async {
        let fixture = await PullRequestsSnapshotFixture()
        fixture.viewModel.selectStatusFilter(.merged)

        assertMacSnapshot(
            PullRequestsFilterPopover(viewModel: fixture.viewModel),
            size: CGSize(width: 260, height: 300),
            named: "pull_requests_filter_popover"
        )
    }

    func testPullRequestsScreenWarningBanner() async {
        let fixture = await PullRequestsSnapshotFixture(
            warnings: ["Resource protected by organization SAML enforcement."]
        )

        assertMacSnapshot(
            fixture.screen,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_warning_banner"
        )
    }
}

@MainActor
private final class PullRequestsSnapshotFixture {
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    let viewModel: PullRequestsViewModel

    var screen: some View {
        PullRequestsScreen(viewModel: viewModel, onOpenGitSettings: {})
    }

    init(
        summaries: [PullRequestSummary]? = nil,
        warnings: [String] = [],
        failure: PullRequestsServiceError? = nil
    ) async {
        let service = SnapshotPullRequestsService()
        if let failure {
            service.listResult = .failure(failure)
        } else {
            service.listResult = .success(PullRequestListResult(
                summaries: summaries ?? Self.defaultSummaries,
                warnings: warnings
            ))
        }
        viewModel = PullRequestsViewModel(
            service: service,
            avatarLoader: GitHubAvatarLoader(),
            // Zero so a baseline that sets `searchQuery` renders the narrowed list in the same
            // turn, with no debounce to wait out before the snapshot is taken.
            searchDebounce: .zero,
            now: { Self.referenceDate }
        )
        // These baselines exercise row rendering across every status glyph, not the packaged
        // open-only default, so the filter is widened before the rows land.
        viewModel.selectStatusFilter(.all)
        await viewModel.refresh()
    }

    static let defaultSummaries: [PullRequestSummary] = [
        makeSummary(
            number: 41,
            repo: "octo/alveary",
            title: "Add pull request browsing to the sidebar",
            author: "afollestad",
            branch: "af/pull-requests",
            status: .open,
            ageMinutes: 25,
            additions: 482,
            deletions: 37,
            isAuthored: true
        ),
        makeSummary(
            number: 128,
            repo: "octo/knit",
            title: "Use swiftlang SwiftSyntax repository",
            author: "kanna",
            branch: "swift-syntax-migration",
            status: .draft,
            ageMinutes: 60 * 5,
            additions: 3,
            deletions: 3,
            isReviewRequested: true
        ),
        makeSummary(
            number: 566,
            repo: "octo/paraphrase",
            title: "Localize plural rules for release notes",
            author: "miguel",
            branch: "plural-rules",
            status: .open,
            ageMinutes: 60 * 24 * 2,
            additions: 120,
            deletions: 44,
            isReviewRequested: true
        ),
        makeSummary(
            number: 9,
            repo: "octo/alveary",
            title: "Drop macOS floor to 15",
            author: "afollestad",
            branch: "af/macos-15",
            status: .merged,
            ageMinutes: 60 * 24 * 33,
            additions: 2,
            deletions: 2,
            isAuthored: true,
            hasReviewed: false
        ),
        makeSummary(
            number: 87,
            repo: "octo/knit",
            title: "Reject cyclic assembly graphs with a diagnostic",
            author: "priya",
            branch: "cycle-diagnostics",
            status: .closed,
            ageMinutes: 60 * 24 * 400,
            additions: 58,
            deletions: 12,
            hasReviewed: true
        )
    ]

    private static func makeSummary(
        number: Int,
        repo: String,
        title: String,
        author: String = "alice",
        branch: String,
        status: PullRequestStatus = .open,
        ageMinutes: Double,
        additions: Int = 10,
        deletions: Int = 3,
        isAuthored: Bool = false,
        isReviewRequested: Bool = false,
        hasReviewed: Bool = false
    ) -> PullRequestSummary {
        let parts = repo.split(separator: "/")
        return PullRequestSummary(
            id: PullRequestIdentifier(owner: String(parts[0]), repo: String(parts[1]), number: number),
            title: title,
            url: nil,
            status: status,
            authorLogin: author,
            // Avatar URLs stay nil so snapshots render the deterministic letter placeholder.
            authorAvatarURL: nil,
            headRefName: branch,
            baseRefName: "main",
            updatedAt: referenceDate.addingTimeInterval(-ageMinutes * 60),
            additions: additions,
            deletions: deletions,
            reviewDecision: nil,
            isAuthored: isAuthored,
            isReviewRequested: isReviewRequested,
            hasReviewed: hasReviewed
        )
    }
}

@MainActor
private final class SnapshotPullRequestsService: PullRequestsService, @unchecked Sendable {
    var listResult: Result<PullRequestListResult, PullRequestsServiceError> = .success(
        PullRequestListResult(summaries: [], warnings: [])
    )

    func listInvolvedPullRequests(
        buckets: Set<PullRequestInvolvementBucket>,
        status: PullRequestStatus?
    ) async throws -> PullRequestListResult {
        let result = try listResult.get()
        // Answer only what was asked for, like the real service and `StubPullRequestsService`.
        // The view model fetches one bucket per request and indexes the reply by bucket, so
        // returning the whole fixture happens to work — but a fake that ignores its arguments
        // stops the next change from being caught here.
        return PullRequestListResult(
            summariesByBucket: result.summariesByBucket.filter { buckets.contains($0.key) },
            warnings: result.warnings
        )
    }

    func fetchDetail(_ id: PullRequestIdentifier) async throws -> PullRequestDetail {
        throw PullRequestsServiceError.transport("unused")
    }

    func fetchDiff(_ id: PullRequestIdentifier) async throws -> String {
        throw PullRequestsServiceError.transport("unused")
    }

    func submitReview(_ id: PullRequestIdentifier, event: PullRequestReviewEvent, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func createPendingReview(pullRequestNodeID: String) async throws -> String {
        throw PullRequestsServiceError.transport("unused")
    }

    func addPendingReviewComment(
        reviewNodeID: String,
        path: String,
        line: Int,
        side: PullRequestDiffSide,
        body: String
    ) async throws -> PullRequestReviewThread {
        throw PullRequestsServiceError.transport("unused")
    }

    func updatePendingReviewComment(commentNodeID: String, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deletePendingReviewComment(commentNodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deletePendingReview(reviewNodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func submitPendingReview(
        reviewNodeID: String,
        event: PullRequestReviewEvent,
        body: String
    ) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deleteReviewComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func addIssueComment(_ id: PullRequestIdentifier, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateIssueComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func deleteIssueComment(_ id: PullRequestIdentifier, commentID: Int) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updateReview(_ id: PullRequestIdentifier, reviewID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func updatePullRequestBody(_ id: PullRequestIdentifier, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func setPullRequestClosed(_ id: PullRequestIdentifier, closed: Bool) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func markPullRequestReadyForReview(nodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func convertPullRequestToDraft(nodeID: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func addReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func removeReaction(subjectID: String, content: PullRequestReactionContent) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func replyToReviewComment(_ id: PullRequestIdentifier, commentID: Int, body: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func setReviewThreadResolved(threadID: String, resolved: Bool) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func requestReview(_ id: PullRequestIdentifier, reviewerLogin: String) async throws {
        throw PullRequestsServiceError.transport("unused")
    }

    func createPullRequest(
        inDirectory directory: String,
        baseBranch: String,
        headBranch: String,
        title: String,
        body: String
    ) async throws -> PullRequestIdentifier {
        throw PullRequestsServiceError.transport("unused")
    }
}
