import SwiftData
import XCTest

@testable import Alveary

/// A pane renders a pending proposal's staged comments because the proposal names its pull
/// request — not because of how the pane was opened. A jump from the transcript card adds only the
/// scroll to the comment that was clicked.
@MainActor
extension PullRequestsViewModelTests {
    /// The toolbar, the links popover, and the list all reach this same path, so the ordinary open
    /// covers every manual route.
    func testAnOrdinarilyOpenedPaneResolvesThePendingProposal() async throws {
        let fixture = try ReviewProposalAttachmentFixture()

        await fixture.openPane()

        XCTAssertEqual(
            fixture.viewModel.activePendingReviewProposal?.id,
            ReviewProposalAttachmentFixture.proposalID
        )
        // Nothing was jumped to, so no scroll is armed.
        XCTAssertNil(fixture.session?.pendingCommentScrollTarget)
    }

    func testAJumpArmsAScrollToTheClickedComment() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let anchor = DiffCommentAnchor(path: "File0.swift", side: .right, line: 1)

        fixture.viewModel.requestCommentScroll(to: anchor, target: fixture.target)

        let scrollTarget = try XCTUnwrap(fixture.session?.pendingCommentScrollTarget)
        XCTAssertEqual(scrollTarget.anchor, anchor)
        XCTAssertEqual(scrollTarget.rowID, "comment:\(anchor.key)")
    }

    /// Resolved on every read through the coordinator, so confirming or rejecting anywhere drops
    /// the staged comments here with no observer to keep in sync.
    func testResolvingTheProposalElsewhereDropsItFromThePane() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        XCTAssertNotNil(fixture.viewModel.activePendingReviewProposal)

        XCTAssertTrue(fixture.coordinator.reject(proposalID: ReviewProposalAttachmentFixture.proposalID))

        XCTAssertNil(fixture.viewModel.activePendingReviewProposal)
    }

    /// A retained session can outlive the pane, so an ordinary reopen must not inherit an unfired
    /// jump and scroll somewhere the user did not ask for.
    func testReopeningClearsAnUnfiredScroll() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.viewModel.requestCommentScroll(
            to: DiffCommentAnchor(path: "File0.swift", side: .right, line: 1),
            target: fixture.target
        )
        XCTAssertNotNil(fixture.session?.pendingCommentScrollTarget)

        // Reopening the same target reuses the retained session.
        fixture.viewModel.requestDetails(fixture.summary)

        XCTAssertNil(fixture.session?.pendingCommentScrollTarget)
        // The proposal still resolves — which comments render never depended on the route.
        XCTAssertNotNil(fixture.viewModel.activePendingReviewProposal)
    }

    /// A proposal naming a different pull request cannot describe this pane.
    func testAProposalForAnotherPullRequestDoesNotResolve() async throws {
        let fixture = try ReviewProposalAttachmentFixture(proposalNumber: 99)

        await fixture.openPane()

        XCTAssertNil(fixture.viewModel.activePendingReviewProposal)
    }

    /// Only the consumer holding the current token may clear it, so a late consumption cannot
    /// swallow a newer request.
    func testOnlyTheMatchingTokenConsumesTheScrollTarget() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        fixture.viewModel.requestCommentScroll(to: DiffCommentAnchor(path: "File0.swift", side: .right, line: 1))
        let stale = try XCTUnwrap(fixture.session?.pendingCommentScrollTarget?.token)

        fixture.viewModel.requestCommentScroll(to: DiffCommentAnchor(path: "File0.swift", side: .right, line: 1))
        fixture.viewModel.consumeCommentScrollTarget(token: stale)

        XCTAssertNotNil(fixture.session?.pendingCommentScrollTarget)

        let current = try XCTUnwrap(fixture.session?.pendingCommentScrollTarget?.token)
        fixture.viewModel.consumeCommentScrollTarget(token: current)
        XCTAssertNil(fixture.session?.pendingCommentScrollTarget)
    }

    /// A comment row is only emitted from a rendered line row, so the anchor's file has to be
    /// inside the paging window and expanded before the scroll can land.
    func testRevealingAnAnchorGrowsThePagingWindowAndExpandsTheFile() async throws {
        let fileCount = PullRequestDiffFilePaging.initialFileCount + 4
        let fixture = try ReviewProposalAttachmentFixture(fileCount: fileCount)
        await fixture.openPane()
        let lastIndex = fileCount - 1
        let anchor = DiffCommentAnchor(path: "File\(lastIndex).swift", side: .right, line: 1)
        let files = try XCTUnwrap(fixture.session?.diffFiles)
        let collapseID = FlattenedDiffPreviewRows.fileCollapseID(for: files[lastIndex], fileIndex: lastIndex)
        fixture.viewModel.mutateSession(fixture.target) { $0.collapsedDiffFileIDs.insert(collapseID) }
        XCTAssertLessThan(try XCTUnwrap(fixture.session?.renderedDiffFileCount), fileCount)

        fixture.viewModel.requestCommentScroll(to: anchor)

        XCTAssertEqual(fixture.session?.renderedDiffFileCount, fileCount)
        XCTAssertFalse(try XCTUnwrap(fixture.session?.collapsedDiffFileIDs).contains(collapseID))
    }

    /// A pull request pushed to since the proposal was made can strand an anchor. Revealing has
    /// nothing to do then, and must not disturb the window it cannot help.
    func testRevealingAnUnmatchedAnchorChangesNothing() async throws {
        let fixture = try ReviewProposalAttachmentFixture()
        await fixture.openPane()
        let before = fixture.session?.renderedDiffFileCount

        fixture.viewModel.requestCommentScroll(to: DiffCommentAnchor(path: "Gone.swift", side: .right, line: 4))

        XCTAssertEqual(fixture.session?.renderedDiffFileCount, before)
        // The scroll is still armed; the consumer gives up once the diff loads without the row.
        XCTAssertNotNil(fixture.session?.pendingCommentScrollTarget)
    }
}

/// A pane opened on a pull request that a pending review proposal also names.
@MainActor
final class ReviewProposalAttachmentFixture {
    static let proposalID = "proposal-1"

    let service = StubPullRequestsService()
    let coordinator: PullRequestReviewProposalCoordinator
    let viewModel: PullRequestsViewModel
    let summary: PullRequestSummary
    private let modelContext: ModelContext

    var target: PullRequestPaneTarget {
        .details(summary.id)
    }

    var session: PullRequestPaneSession? {
        viewModel.paneSessions[target]
    }

    /// `proposalNumber` defaults to the pane's own pull request; pass another to cover a
    /// proposal that cannot describe this pane.
    init(fileCount: Int = 2, proposalNumber: Int? = nil) throws {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        modelContext = context
        summary = makePullRequestSummary(number: 7)

        let thread = AgentThread(name: "Thread")
        let conversation = Conversation(id: "source-conversation", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        try conversation.storePullRequestReviewProposal(
            Self.record(nameWithOwner: summary.id.nameWithOwner, number: proposalNumber ?? summary.id.number)
        )
        try context.save()

        coordinator = PullRequestReviewProposalCoordinator(
            modelContext: context,
            pullRequestsService: service,
            notificationCenter: NotificationCenter(),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: fileCount))
        viewModel = makePullRequestsViewModel(service: service, reviewProposalCoordinator: coordinator)
    }

    func openPane() async {
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
    }

    /// One staged comment on `File0.swift:1`, the first line `makeUnifiedDiffFixture` emits.
    private static func record(nameWithOwner: String, number: Int) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: proposalID,
            deduplicationKey: "dedup-1",
            repositoryNameWithOwner: nameWithOwner,
            number: number,
            event: "comment",
            body: "Some notes.",
            comments: [
                PullRequestReviewProposalRecord.Comment(
                    path: "File0.swift",
                    line: 1,
                    side: "RIGHT",
                    body: "Staged remark"
                )
            ],
            titleSnapshot: "Detail title",
            pendingCommentCountSnapshot: 0,
            sourceProviderID: "codex",
            sourceProcessToken: "token",
            sourceRequestID: "request-1",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
