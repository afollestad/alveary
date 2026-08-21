import SwiftData
import XCTest

@testable import Alveary

/// Publishing a review holds its thread still. A proposal merely waiting on the user does not —
/// dismissing the card is how that ends — so only the span `confirm` spends inside GitHub blocks
/// archive and delete, the rule an active scheduled run already follows.
///
/// These drive the real notification, not an injected set: `PullRequestReviewSubmissionActivity`
/// derives its whole state from that broadcast, so posting is what proves the wiring. Every test
/// closes the span it opens, because the shared instance outlives the test.
@MainActor
extension SidebarViewModelTests {
    private func beginSubmission(conversationID: String) {
        postSubmissionChange(conversationID: conversationID, isSubmitting: true)
    }

    private func endSubmission(conversationID: String) {
        postSubmissionChange(conversationID: conversationID, isSubmitting: false)
    }

    private func postSubmissionChange(conversationID: String, isSubmitting: Bool) {
        NotificationCenter.default.post(
            name: .pullRequestReviewSubmissionChanged,
            object: nil,
            userInfo: [
                PullRequestReviewSubmissionKey.conversationID: conversationID,
                PullRequestReviewSubmissionKey.isSubmitting: isSubmitting
            ]
        )
    }

    private func makeReviewingThread(in fixture: SidebarTestFixture, conversationID: String) throws -> AgentThread {
        let thread = AgentThread(name: "Reviewing")
        thread.conversations = [Conversation(id: conversationID, provider: "codex", thread: thread)]
        fixture.context.insert(thread)
        try fixture.context.save()
        return thread
    }

    /// Deleting a project-mode thread resolves its parent, so these need one; archiving does not.
    private func makeDeletableReviewingThread(
        in fixture: SidebarTestFixture,
        conversationID: String
    ) throws -> AgentThread {
        let project = Project(path: "/tmp/review-submission-\(conversationID)", name: "Reviewed")
        let thread = AgentThread(name: "Reviewing", project: project)
        thread.conversations = [Conversation(id: conversationID, provider: "codex", thread: thread)]
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        return thread
    }

    func testAnInFlightSubmissionBlocksArchiveAndDelete() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "submitting-conversation")

        beginSubmission(conversationID: "submitting-conversation")
        defer { endSubmission(conversationID: "submitting-conversation") }

        XCTAssertEqual(
            fixture.viewModel.threadCleanupBlockedReason(for: thread),
            "This thread is submitting a pull request review. Wait for it to finish before archiving or deleting this thread."
        )
        XCTAssertThrowsError(try fixture.viewModel.requireThreadLifecycleIsUnblocked(thread)) { error in
            guard case .activeReviewSubmission = error as? SidebarViewModelError else {
                return XCTFail("Expected activeReviewSubmission, got \(error)")
            }
        }
    }

    /// The span closes on `confirm`'s `defer`, including the failure path, so the thread must be
    /// releasable the moment it does.
    func testTheThreadIsReleasedWhenTheSubmissionEnds() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "finished-conversation")

        beginSubmission(conversationID: "finished-conversation")
        XCTAssertNotNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))

        endSubmission(conversationID: "finished-conversation")

        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
        XCTAssertNoThrow(try fixture.viewModel.requireThreadLifecycleIsUnblocked(thread))
    }

    /// A card sitting unconfirmed is not work in flight, so it must not pin its thread in the
    /// sidebar — rejecting it is how the user ends it, and archiving does that for them.
    func testAPendingProposalAloneDoesNotBlockTheThread() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "pending-only-conversation")

        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
        XCTAssertNoThrow(try fixture.viewModel.requireThreadLifecycleIsUnblocked(thread))
    }

    /// Two windows can each hold a coordinator announcing for one conversation, so the span is
    /// counted rather than a flag — the first `defer` must not release a thread the other submit
    /// is still inside.
    func testASecondSubmissionKeepsTheThreadHeldUntilBothEnd() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "two-windows-conversation")

        beginSubmission(conversationID: "two-windows-conversation")
        beginSubmission(conversationID: "two-windows-conversation")
        endSubmission(conversationID: "two-windows-conversation")

        XCTAssertNotNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))

        endSubmission(conversationID: "two-windows-conversation")

        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
    }

    /// An end with no matching begin — a coordinator built while a submit was already running —
    /// must not drive the count below zero and wedge the conversation as permanently blocked.
    func testAnUnpairedEndCannotWedgeTheConversation() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "unpaired-conversation")

        endSubmission(conversationID: "unpaired-conversation")
        beginSubmission(conversationID: "unpaired-conversation")
        defer { endSubmission(conversationID: "unpaired-conversation") }

        XCTAssertNotNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
    }

    /// A thread owns several conversations and any one of them mid-submit holds it.
    func testASiblingConversationsSubmissionBlocksTheThread() throws {
        let fixture = try SidebarTestFixture()
        let thread = AgentThread(name: "Two conversations")
        thread.conversations = [
            Conversation(id: "quiet-conversation", provider: "codex", thread: thread),
            Conversation(id: "busy-conversation", provider: "codex", thread: thread)
        ]
        fixture.context.insert(thread)
        try fixture.context.save()

        beginSubmission(conversationID: "busy-conversation")
        defer { endSubmission(conversationID: "busy-conversation") }

        XCTAssertNotNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
    }

    /// An unrelated thread stays archivable while another one publishes.
    func testAnUnrelatedThreadIsUnaffected() throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "bystander-conversation")

        beginSubmission(conversationID: "somebody-elses-conversation")
        defer { endSubmission(conversationID: "somebody-elses-conversation") }

        XCTAssertNil(fixture.viewModel.threadCleanupBlockedReason(for: thread))
    }

    // MARK: - Archiving dismisses the card

    /// The envelope otherwise survives archiving, and the proposal lookup does not filter archived
    /// threads — so the pull request pane kept badging the staged comments "Proposed" and offering a
    /// Submit for a card the sidebar no longer reaches.
    func testArchivingRejectsThePendingProposal() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "archived-conversation")
        let conversation = try XCTUnwrap(thread.conversations.first)
        try conversation.storePullRequestReviewProposal(Self.archivedProposalRecord())
        try fixture.context.save()

        try await fixture.viewModel.archiveThread(thread)

        XCTAssertNil(try conversation.pullRequestReviewProposal())
        XCTAssertNotNil(thread.archivedAt)
    }

    /// The dismissal is recorded, so the archived thread's transcript resolves its card as
    /// "Review not submitted" rather than leaving it pending forever.
    func testArchivingWritesTheDismissalMarker() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "marked-conversation")
        let conversation = try XCTUnwrap(thread.conversations.first)
        try conversation.storePullRequestReviewProposal(Self.archivedProposalRecord())
        try fixture.context.save()

        try await fixture.viewModel.archiveThread(thread)

        let markers = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.hostToolOutcomeType
        }
        XCTAssertEqual(markers.map(\.toolId), [Self.archivedProposalID])
    }

    /// The guard wins over the dismissal: a refused archive must leave the review it was about to
    /// abandon exactly as it found it.
    func testArchivingMidSubmitIsRefusedAndClearsNothing() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "midsubmit-conversation")
        let conversation = try XCTUnwrap(thread.conversations.first)
        try conversation.storePullRequestReviewProposal(Self.archivedProposalRecord())
        try fixture.context.save()

        beginSubmission(conversationID: "midsubmit-conversation")
        defer { endSubmission(conversationID: "midsubmit-conversation") }

        do {
            try await fixture.viewModel.archiveThread(thread)
            XCTFail("Expected the archive to be refused")
        } catch {
            guard case .activeReviewSubmission = error as? SidebarViewModelError else {
                return XCTFail("Expected activeReviewSubmission, got \(error)")
            }
        }

        XCTAssertNotNil(try conversation.pullRequestReviewProposal())
        XCTAssertNil(thread.archivedAt)
    }

    /// Archiving a thread that never held one writes no marker.
    func testArchivingWithoutAProposalRecordsNothing() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeReviewingThread(in: fixture, conversationID: "plain-conversation")

        try await fixture.viewModel.archiveThread(thread)

        let markers = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertTrue(markers.isEmpty)
        XCTAssertNotNil(thread.archivedAt)
    }

    /// Deleting cascades the envelope away, but every window's coordinator still holds the
    /// presentation in memory and nothing else tells it to re-read — so the pull request pane kept
    /// offering Submit for a deleted thread's review. Archiving announces from its own path.
    func testDeletingAThreadAnnouncesThatProposalsChanged() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeDeletableReviewingThread(in: fixture, conversationID: "deleted-conversation")
        let conversation = try XCTUnwrap(thread.conversations.first)
        try conversation.storePullRequestReviewProposal(Self.archivedProposalRecord())
        try fixture.context.save()

        let recorder = ReviewProposalChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .pullRequestReviewProposalsChanged,
            object: nil,
            queue: nil
        ) { [recorder] _ in recorder.record() }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(recorder.count, 1)
    }

    /// A thread that held none announces nothing, so an ordinary delete does not make every window
    /// re-read its proposals.
    func testDeletingAThreadWithoutAProposalAnnouncesNothing() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeDeletableReviewingThread(in: fixture, conversationID: "plain-deleted-conversation")

        let recorder = ReviewProposalChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: .pullRequestReviewProposalsChanged,
            object: nil,
            queue: nil
        ) { [recorder] _ in recorder.record() }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(recorder.count, 0)
    }

    private static let archivedProposalID = "archived-proposal"

    private static func archivedProposalRecord() -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: PullRequestReviewProposalRecord.currentPayloadVersion,
            id: archivedProposalID,
            deduplicationKey: "dedup-archived",
            repositoryNameWithOwner: "octo/alveary",
            number: 7,
            event: "comment",
            body: "Some notes.",
            comments: nil,
            titleSnapshot: "Detail title",
            pendingCommentCountSnapshot: 0,
            sourceProviderID: "codex",
            sourceProcessToken: "token",
            sourceRequestID: "request-archived",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

/// Counts `.pullRequestReviewProposalsChanged` posts. Lock-backed for the same reason
/// `ScheduledTaskChangeRecorder` is: the observer block is `@Sendable`, so a captured `var` cannot
/// be mutated from it.
private final class ReviewProposalChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0

    var count: Int {
        lock.withLock { recorded }
    }

    func record() {
        lock.withLock { recorded += 1 }
    }
}
