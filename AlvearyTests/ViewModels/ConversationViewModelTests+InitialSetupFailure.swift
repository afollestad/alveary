import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    /// The runtime arms a turn when it installs the spawn's event buffer, before the provider
    /// process starts. A failed spawn emits no terminal event, so without an explicit rollback the
    /// composer stays busy forever — and a busy conversation fails `canApplyPreStartupSettingChange`,
    /// which is what made the reasoning menu's cross-provider picks silently no-op on a pull request
    /// agentic-review thread whose Codex `thread/start` failed.
    func testFailedInitialSetupEndsOptimisticTurnAndAllowsProviderSwitch() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            providerId: "codex"
        )
        let state = fixture.viewModel.state
        await fixture.agentsManager.setSpawnPrologue { state.turnState.beginTurn() }
        await fixture.agentsManager.enqueueSpawnError(MockAgentsManager.MockError.sendFailed)

        do {
            try await fixture.viewModel.setupAndStart("Review pull request: https://example.com/pull/1")
            XCTFail("Expected initial setup to throw")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.isAgentActivelyWorking)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
        XCTAssertNil(fixture.viewModel.setupPhase)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)

        // The rollback records no terminal boundary, and it must not: there is no transcript error
        // row and no turn, so a red sidebar dot on a thread reset to "never sent" would be a lie.
        XCTAssertNil(fixture.conversation.lastTurnFailedAt)

        // The thread and its attempted message survive; only the phantom turn is gone.
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageIDs.count, 1)
        XCTAssertNotNil(fixture.viewModel.state.lastTurnError)

        // The reported symptom was progress dots plus a Stop button that never went away, so pin
        // the composer mode itself rather than only the flags feeding it.
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(composerMode(for: fixture.viewModel), .idle)

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "claude",
            model: "sonnet",
            effortOptions: AgentModelOptionTestFixtures.claudeSonnetEfforts,
            defaultEffort: AgentModelOptionTestFixtures.high.value
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(try fixture.dbConversation().provider, "claude")
        XCTAssertEqual(try fixture.dbThread().model, "sonnet")
    }

    /// Cancellation already recovered, because its branch replaces `ConversationState` outright.
    /// The rollback now runs after both branches, so this pins that it stays clean.
    func testCancelledInitialSetupLeavesNoActiveTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            providerId: "codex"
        )
        let state = fixture.viewModel.state
        await fixture.agentsManager.setSpawnPrologue { state.turnState.beginTurn() }
        await fixture.agentsManager.enqueueSpawnError(CancellationError())

        do {
            try await fixture.viewModel.setupAndStart("Review pull request: https://example.com/pull/1")
            XCTFail("Expected initial setup to throw")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.isAgentActivelyWorking)
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
    }

    /// Mirrors `ChatView.composerMode`, minus the pending-approval text the caller asserts is absent.
    private func composerMode(for viewModel: ConversationViewModel) -> ComposerMode {
        ChatPresentation.composerMode(for: ChatComposerModeState(
            isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup,
            hasSetupPhase: viewModel.setupPhase != nil,
            isReconfiguringSession: viewModel.state.isReconfiguringSession,
            isAwaitingHandoffSteering: viewModel.state.isAwaitingHandoffSteering,
            isHandingOffSession: viewModel.state.isHandingOffSession,
            isAwaitingExitPlanModeFollowUp: viewModel.state.isAwaitingExitPlanModeFollowUp,
            pendingToolApprovalStatusText: nil,
            isTurnActive: viewModel.turnState.isActive,
            runtimeStatus: viewModel.agentsManager.status(for: viewModel.conversation.id),
            isSendingMessage: viewModel.state.isSendingMessage
        ))
    }
}
