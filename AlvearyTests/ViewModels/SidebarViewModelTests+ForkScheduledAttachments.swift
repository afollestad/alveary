import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testForkRollbackPreservesTargetAndWorktreeWhenScheduleAttachesDuringSpawn() async throws {
        let setup = try projectForkSetup(providerId: .codex, sessionId: "codex-thread")
        let fixture = setup.fixture
        let observation = ForkAttachmentObservation()
        await configureAttachedForkFailure(fixture: fixture, observation: observation)

        do {
            _ = try await fixture.viewModel.forkThreadIntoWorktree(setup.thread)
            XCTFail("Expected provider bootstrap failure")
        } catch let error as SidebarViewModelError {
            guard case .threadForkRollbackFailed(_, let cleanup) = error else {
                return XCTFail("Expected rollback to fail closed, got \(error)")
            }
            XCTAssertEqual(
                cleanup.localizedDescription,
                "The forked thread became attached to a scheduled task, so rollback preserved it."
            )
        }

        XCTAssertNil(observation.error)
        let targetID = try XCTUnwrap(observation.targetID)
        let definitionID = try XCTUnwrap(observation.definitionID)
        let target = try XCTUnwrap(fixture.context.resolveThread(id: targetID))
        let definition = try XCTUnwrap(fixture.context.resolveScheduledTask(id: definitionID))
        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertTrue(target.isForkBootstrapPending)
        XCTAssertFalse(target.hasCompletedInitialSetup)
        let removeCalls = await fixture.worktreeManager.removeCalls()
        let providerActions = await fixture.providerSessionActions.actions
        XCTAssertEqual(removeCalls, [])
        XCTAssertFalse(providerActions.contains { action in
            if case .delete = action {
                return true
            }
            return false
        })
    }
}

@MainActor
private func configureAttachedForkFailure(
    fixture: SidebarTestFixture,
    observation: ForkAttachmentObservation
) async {
    await fixture.agentsManager.setSpawnError(.spawnFailed("fork failed"))
    await fixture.worktreeManager.setCreateInfo(WorktreeInfo(
        path: "/tmp/attached-fork-worktree",
        branch: "alveary/attached-fork"
    ))
    await fixture.agentsManager.setSpawnObserver { conversationID in
        do {
            let conversation = try fixture.requireConversation(id: conversationID)
            let target = try XCTUnwrap(conversation.thread)
            XCTAssertTrue(target.isForkBootstrapPending)
            XCTAssertFalse(target.hasCompletedInitialSetup)
            target.isPinned = true
            let definition = ScheduledTask(
                title: "Attached during fork",
                prompt: "Continue in the forked thread.",
                destination: .existingThread,
                recurrence: .daily(hour: 9, minute: 0),
                timeZoneIdentifier: "America/Chicago",
                providerID: "codex",
                targetThread: target
            )
            fixture.context.insert(definition)
            try fixture.context.save()
            observation.targetID = target.persistentModelID
            observation.definitionID = definition.id
        } catch {
            observation.error = error
        }
    }
}

@MainActor
private final class ForkAttachmentObservation {
    var error: Error?
    var targetID: PersistentIdentifier?
    var definitionID: String?
}
