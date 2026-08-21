import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// Contract coverage for the status fold, the sidebar's pass-start liveness filter, and the
/// tab/transcript value snapshots — the surfaces the 0.2.2 (11) notification-click crash proved
/// exposed. Same doctrine as the base file: structural locks, not reproductions.
@MainActor
extension DeletedModelRenderSafetyTests {
    // MARK: - Pass-start liveness filter

    /// The filter's load-bearing assumption, verified: a delete pending in the context is
    /// `isDeleted`, and a *committed* delete leaves the instance with no `modelContext`. Both
    /// states must fall outside `isLiveForRender`, or `makeRenderContext()`'s filter would pass
    /// dead rows to the pinned-item walk that crashed.
    func testCommittedDeleteLeavesRowOutsideRenderLiveness() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-liveness"
        )
        XCTAssertTrue(thread.isLiveForRender)

        fixture.context.delete(thread)
        XCTAssertFalse(thread.isLiveForRender)

        try fixture.context.save()
        XCTAssertNil(thread.modelContext)
        XCTAssertFalse(thread.isLiveForRender)
    }

    // MARK: - Status fold

    /// The fold accepts no models, so it answers from snapshots taken while rows were live even
    /// after the rows die — the compile-level lock on the sidebar status path. `lastTurnFailedAt`
    /// is seeded too, so the durable failure input stays inside that contract; the pending decision
    /// still outranks it.
    func testThreadStatusFoldedAnswersFromValueSnapshotsAfterDelete() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-fold",
            conversationIDs: ["unread", "deciding"]
        )
        thread.conversations.first { $0.id == "unread" }?.isUnread = true
        thread.conversations.first { $0.id == "deciding" }?.lastTurnFailedAt = Date()
        try fixture.context.save()

        let attention = ConversationDecisionAttention(
            unresolvedApprovalConversationIDs: [],
            scheduledProposalConversationIDs: ["deciding"],
            reviewProposalConversationIDs: [],
            showsPullRequestLinkPrompts: false
        )
        let snapshots = thread.conversations.map {
            ConversationStatusSnapshot(conversation: $0, attention: attention, activity: .none)
        }

        fixture.context.delete(thread)
        try fixture.context.save()

        XCTAssertEqual(
            ThreadStatus.folded(isArchived: false, conversations: snapshots) { _ in .neutral },
            .waitingForUser
        )
    }

    /// A row whose conversations died mid-pass folds `[]`, degrading to `.stopped` instead of
    /// reading anything.
    func testThreadStatusForUnknownThreadDegradesToStopped() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-degrade"
        )
        let threadID = thread.persistentModelID

        fixture.context.delete(thread)
        try fixture.context.save()

        XCTAssertEqual(
            fixture.viewModel.threadStatus(threadID: threadID, isArchived: false, conversationStatuses: []),
            .stopped
        )
    }

    /// Executes the shared sidebar conversations predicate against a real store, so a
    /// translation failure (the `#Predicate` TERNARY class from `Alveary/Data/AGENTS.md`) fails
    /// here instead of on the first render pass.
    func testSidebarStatusFoldConversationsPredicateExcludesArchivedThreads() throws {
        let fixture = try SidebarTestFixture()
        _ = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-predicate",
            conversationIDs: ["active-main", "active-side"]
        )
        let archived = try fixture.insertThread(
            projectName: "Other",
            projectPath: "/tmp/alveary-predicate-archived",
            conversationIDs: ["archived-main"]
        )
        try fixture.markThreadArchived(archived)

        let fetched = try fixture.context.fetch(
            FetchDescriptor<Conversation>(predicate: sidebarStatusFoldConversationsPredicate)
        )

        XCTAssertEqual(Set(fetched.map(\.id)), ["active-main", "active-side"])
    }

    // MARK: - Conversation tab presentations

    /// Mirror of `testThreadRowPresentationStillReadsAfterItsThreadIsDeleted` for the chip strip.
    func testConversationTabPresentationStillReadsAfterConversationDelete() throws {
        let fixture = try ConversationViewModelTestFixture(conversationTitle: "Main `code`")
        let conversation = fixture.conversation
        let tab = ConversationTabPresentation(conversation: conversation, status: .unread)

        fixture.context.delete(conversation)
        try fixture.context.save()

        XCTAssertEqual(tab.displayName, "Main `code`")
        XCTAssertEqual(tab.plainDisplayName, "Main code")
        XCTAssertEqual(tab.renameSeedText, "Main `code`")
        XCTAssertEqual(tab.status, .unread)
        XCTAssertTrue(tab.canRemove)
    }

    // MARK: - Transcript identity snapshots

    /// The transcript bridge reads identity through these `let` snapshots, so a revision-driven
    /// body re-run after a delete has values to answer with.
    func testConversationViewModelIdentitySnapshotsSurviveConversationDelete() throws {
        let fixture = try ConversationViewModelTestFixture()
        let expectedConversationID = fixture.conversation.id
        let expectedThreadModelID = fixture.thread.persistentModelID

        fixture.context.delete(fixture.conversation)
        fixture.context.delete(fixture.thread)
        try fixture.context.save()

        XCTAssertEqual(fixture.viewModel.conversationID, expectedConversationID)
        XCTAssertEqual(fixture.viewModel.threadModelID, expectedThreadModelID)
    }
}
