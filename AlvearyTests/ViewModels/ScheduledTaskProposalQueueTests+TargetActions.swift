import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskProposalQueueTests {
    func testRejectConsumesProposalWithoutChangingTargetDefinition() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "target", revision: 4)
        let originalModifiedAt = definition.modifiedAt
        let proposal = try fixture.insertTargetProposal(
            id: "reject-edit",
            action: .edit,
            definition: definition,
            definitionDraft: fixture.makeDefinitionDraft(title: "Unapplied edit")
        )
        let proposalID = proposal.id
        let coordinator = fixture.makeCoordinator()

        coordinator.reject(proposalID: proposalID)

        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        let persistedDefinition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: definition.id))
        XCTAssertEqual(persistedDefinition.title, "Original")
        XCTAssertEqual(persistedDefinition.prompt, "Original prompt")
        XCTAssertEqual(persistedDefinition.state, .active)
        XCTAssertEqual(persistedDefinition.revision, 4)
        XCTAssertEqual(persistedDefinition.modifiedAt, originalModifiedAt)
    }

    func testStaleRevisionConflictKeepsProposalAndDefinitionUnchanged() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "stale-target", revision: 3)
        let proposal = try fixture.insertTargetProposal(
            id: "stale-pause",
            action: .pause,
            definition: definition,
            expectedRevision: 2
        )
        let coordinator = fixture.makeCoordinator()

        XCTAssertTrue(coordinator.currentProposal?.conflictMessage?.contains("changed") == true)

        coordinator.confirmActionProposal(proposalID: proposal.id)

        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 3)
        XCTAssertTrue(coordinator.errorMessage?.contains("changed") == true)
    }

    func testDeletedDefinitionConflictKeepsProposalPending() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let (definitionID, proposalID) = try {
            let definition = try fixture.insertDefinition(id: "deleted-target", revision: 2)
            let proposal = try fixture.insertTargetProposal(
                id: "deleted-run-now",
                action: .runNow,
                definition: definition
            )
            let identifiers = (definition.id, proposal.id)
            fixture.context.delete(definition)
            try fixture.context.save()
            return identifiers
        }()
        let coordinator = fixture.makeCoordinator()

        XCTAssertTrue(coordinator.currentProposal?.conflictMessage?.contains("deleted") == true)

        coordinator.confirmActionProposal(proposalID: proposalID)

        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertNil(fixture.context.resolveScheduledTask(id: definitionID))
        XCTAssertTrue(coordinator.errorMessage?.contains("deleted") == true)
    }

    func testConfirmEditUpdatesDefinitionAndConsumesProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "edit-target", revision: 5)
        let definitionDraft = fixture.makeDefinitionDraft(
            title: "Edited title",
            prompt: "Edited prompt",
            recurrence: .weekdays(hour: 9, minute: 30)
        )
        let proposal = try fixture.insertTargetProposal(
            id: "edit",
            action: .edit,
            definition: definition,
            definitionDraft: definitionDraft
        )
        let proposalID = proposal.id
        let coordinator = fixture.makeCoordinator()
        let viewModel = fixture.makeScheduledTasksViewModel()
        let editorDraft = viewModel.makeProposalDraft(
            definitionDraft,
            definitionID: definition.id,
            expectedRevision: definition.revision
        )

        XCTAssertTrue(
            coordinator.confirmEditorProposal(
                proposalID: proposalID,
                draft: editorDraft,
                viewModel: viewModel
            )
        )

        let persistedDefinition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: definition.id))
        XCTAssertEqual(persistedDefinition.title, definitionDraft.title)
        XCTAssertEqual(persistedDefinition.prompt, definitionDraft.prompt)
        XCTAssertEqual(persistedDefinition.recurrence, definitionDraft.recurrence)
        XCTAssertEqual(persistedDefinition.revision, 6)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
    }

    func testConfirmPauseUpdatesDefinitionAndConsumesProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "pause-target")
        let proposal = try fixture.insertTargetProposal(id: "pause", action: .pause, definition: definition)
        let proposalID = proposal.id
        let coordinator = fixture.makeCoordinator()

        coordinator.confirmActionProposal(proposalID: proposalID)

        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testConfirmResumeUpdatesDefinitionAndConsumesProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "resume-target", state: .paused)
        let proposal = try fixture.insertTargetProposal(id: "resume", action: .resume, definition: definition)
        let proposalID = proposal.id
        let coordinator = fixture.makeCoordinator()

        coordinator.confirmActionProposal(proposalID: proposalID)

        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 2)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertNil(coordinator.errorMessage)
    }

    func testConfirmDeleteRemovesDefinitionAndConsumesProposal() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let (definitionID, proposalID) = try {
            let definition = try fixture.insertDefinition(id: "delete-target")
            let proposal = try fixture.insertTargetProposal(id: "delete", action: .delete, definition: definition)
            return (definition.id, proposal.id)
        }()
        let coordinator = fixture.makeCoordinator()

        coordinator.confirmActionProposal(proposalID: proposalID)

        XCTAssertNil(fixture.context.resolveScheduledTask(id: definitionID))
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertNil(coordinator.currentProposal)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testConfirmRunNowConsumesProposalOnlyWhenSchedulerAcceptsRequest() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(
            id: "run-now-target",
            state: .paused,
            nextOccurrenceAt: fixture.now.addingTimeInterval(60)
        )
        let proposal = try fixture.insertTargetProposal(id: "run-now", action: .runNow, definition: definition)
        let proposalID = proposal.id
        var capturedRequest: ScheduledTaskRunNowRequest?
        let coordinator = fixture.makeCoordinator(runNow: { request in
            capturedRequest = request
            return true
        })

        coordinator.confirmActionProposal(proposalID: proposalID)

        XCTAssertEqual(capturedRequest?.definitionID, definition.id)
        XCTAssertEqual(capturedRequest?.definitionRevision, definition.revision)
        XCTAssertEqual(capturedRequest?.occurrenceSource, .manual)
        XCTAssertEqual(capturedRequest?.idempotencyKey, proposalID)
        XCTAssertNil(fixture.context.resolveScheduledTaskProposal(id: proposalID))
        XCTAssertEqual(definition.state, .paused)
        XCTAssertEqual(definition.revision, 1)
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.now.addingTimeInterval(60))
    }

    func testConfirmRunNowKeepsProposalWhenSchedulerRejectsRequest() throws {
        let fixture = try ScheduledTaskProposalQueueFixture()
        let definition = try fixture.insertDefinition(id: "rejected-run-now-target")
        let proposal = try fixture.insertTargetProposal(
            id: "rejected-run-now",
            action: .runNow,
            definition: definition
        )
        var requestCount = 0
        let coordinator = fixture.makeCoordinator(runNow: { _ in
            requestCount += 1
            return false
        })

        coordinator.confirmActionProposal(proposalID: proposal.id)

        XCTAssertEqual(requestCount, 1)
        XCTAssertNotNil(fixture.context.resolveScheduledTaskProposal(id: proposal.id))
        XCTAssertEqual(coordinator.currentProposal?.id, proposal.id)
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.revision, 1)
    }
}
