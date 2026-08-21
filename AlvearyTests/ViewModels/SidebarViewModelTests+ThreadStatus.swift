import SwiftData
import XCTest

@testable import Alveary

/// The status a sidebar row folds to, end to end through `SidebarViewModel.threadStatus` rather
/// than through `ThreadStatus.folded` directly — `AlvearyTests/Data/ThreadStatusTests.swift` owns
/// the ladder itself, these own that the production path reaches it with the right inputs.
@MainActor
extension SidebarViewModelTests {
    func testThreadStatusUsesDocumentedPriorityAndArchivedOverride() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["busy", "waiting", "error", "unread", "neutral"]
        )
        thread.conversations.first { $0.id == "unread" }?.isUnread = true
        try fixture.context.save()

        await fixture.agentsManager.setStatus(.busy, for: "busy")
        await fixture.agentsManager.setStatus(.waitingForUser, for: "waiting")
        await fixture.agentsManager.setStatus(.error, for: "error")
        XCTAssertEqual(fixture.threadStatus(for: thread), .busy)

        await fixture.agentsManager.setStatus(.neutral, for: "busy")
        XCTAssertEqual(fixture.threadStatus(for: thread), .waitingForUser)

        await fixture.agentsManager.setStatus(.neutral, for: "waiting")
        XCTAssertEqual(fixture.threadStatus(for: thread), .error)

        await fixture.agentsManager.setStatus(.neutral, for: "error")
        XCTAssertEqual(fixture.threadStatus(for: thread), .unread)

        thread.conversations.first { $0.id == "unread" }?.isUnread = false
        try fixture.context.save()
        XCTAssertEqual(fixture.threadStatus(for: thread), .stopped)

        try fixture.markThreadArchived(thread)
        XCTAssertEqual(fixture.threadStatus(for: thread), .archived)
    }

    /// End to end through the real fold: a provider that errors without ending its turn leaves the
    /// runtime reporting `.busy`, and the persisted failure is what turns the row red anyway.
    func testThreadStatusShowsErrorForDurablyFailedConversationWithStaleBusySignal() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-durable-failure",
            conversationIDs: ["failed"]
        )
        thread.conversations.first?.lastTurnFailedAt = Date()
        try fixture.context.save()
        await fixture.agentsManager.setStatus(.busy, for: "failed")

        XCTAssertEqual(fixture.threadStatus(for: thread), .error)
    }

    /// End to end through the real fold: a conversation whose review proposal is publishing spins
    /// the row, rather than keeping the blue dot the pending proposal raised.
    func testThreadStatusSpinsWhileAConversationPublishesAReview() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-publishing-review",
            conversationIDs: ["publishing"]
        )
        let attention = ConversationDecisionAttention(
            unresolvedApprovalConversationIDs: [],
            scheduledProposalConversationIDs: [],
            reviewProposalConversationIDs: ["publishing"],
            showsPullRequestLinkPrompts: false
        )
        XCTAssertEqual(fixture.threadStatus(for: thread, attention: attention), .waitingForUser)

        let activity = ConversationWorkActivity(publishingReviewConversationIDs: ["publishing"])

        XCTAssertEqual(
            fixture.threadStatus(for: thread, attention: attention, activity: activity),
            .busy
        )
    }
}
