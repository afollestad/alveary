import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskProposalQueueTests {
    func testProposalReviewPaneReloadsInPlaceWhenAFollowUpSupersedesTheProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let original = try fixture.insertProposal(
            id: "review",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Original title")
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let presentation = try XCTUnwrap(coordinator.presentation(forProposalID: original.id))

        viewModel.requestProposalReview(presentation, originThreadID: nil)
        let target = try XCTUnwrap(viewModel.activePaneTarget)
        let generation = try XCTUnwrap(viewModel.paneSessions[target]?.generation)
        XCTAssertEqual(viewModel.paneSessions[target]?.draft.title, "Original title")

        // A follow-up prompt replaces the unconfirmed proposal for the same conversation.
        let sourceConversationID = original.sourceConversationID
        fixture.context.delete(original)
        try fixture.context.save()
        let replacement = try fixture.insertProposal(
            id: "review-replacement",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Revised title"),
            sourceConversationID: sourceConversationID
        )

        viewModel.refreshActiveProposalPaneIfNeeded()

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertEqual(viewModel.paneSessions[target]?.generation, generation)
        XCTAssertEqual(viewModel.paneSessions[target]?.draft.title, "Revised title")
        XCTAssertEqual(viewModel.paneSessions[target]?.proposalID, replacement.id)
    }

    func testProposalReviewPaneClosesWhenItsProposalDisappears() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "review-gone",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Going away")
        )
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let presentation = try XCTUnwrap(coordinator.presentation(forProposalID: proposal.id))

        viewModel.requestProposalReview(presentation, originThreadID: nil)
        XCTAssertNotNil(viewModel.activePaneTarget)

        fixture.context.delete(proposal)
        try fixture.context.save()
        viewModel.refreshActiveProposalPaneIfNeeded()

        XCTAssertNil(viewModel.activePaneTarget)
    }

    func testProposalReviewPaneIsScopedToTheThreadThatOpenedIt() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let proposal = try fixture.insertProposal(
            id: "review-scope",
            action: .create,
            definitionDraft: fixture.makeDefinitionDraft(title: "Scoped")
        )
        let thread = AgentThread(name: "Origin")
        let otherThread = AgentThread(name: "Other")
        fixture.context.insert(thread)
        fixture.context.insert(otherThread)
        try fixture.context.save()

        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let presentation = try XCTUnwrap(coordinator.presentation(forProposalID: proposal.id))

        viewModel.requestProposalReview(presentation, originThreadID: thread.persistentModelID)

        XCTAssertNotNil(viewModel.activeTranscriptPaneTarget(forThreadID: thread.persistentModelID))
        XCTAssertNil(viewModel.activeTranscriptPaneTarget(forThreadID: otherThread.persistentModelID))

        // An edit opened from the same transcript is scoped the same way.
        let definition = try fixture.insertDefinition(id: "scoped-edit", revision: 1)
        try fixture.context.save()
        viewModel.requestEditFromTranscript(
            definitionID: definition.id,
            originThreadID: thread.persistentModelID
        )
        XCTAssertEqual(
            viewModel.activeTranscriptPaneTarget(forThreadID: thread.persistentModelID),
            .edit(definition.id)
        )
        XCTAssertNil(viewModel.activeTranscriptPaneTarget(forThreadID: otherThread.persistentModelID))

        // A screen-opened edit is unscoped and stays on the Scheduled screen.
        viewModel.requestEdit(definitionID: definition.id)
        XCTAssertNil(viewModel.proposalPaneOriginThreadID)
    }
}
