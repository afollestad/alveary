import Foundation
import XCTest

@testable import Alveary

@MainActor
final class ConversationViewModelSettingsTests: XCTestCase {
    // Regression test for the composer-dropdown bug where `applyEffortChange`
    // silently dropped the session fork whenever the Claude CLI process had
    // exited between turns. The fork must still happen as long as the thread
    // has completed initial setup.
    func testApplyEffortChangeReconfiguresWhenProcessIsNotRunning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        XCTAssertEqual(try fixture.dbThread().effort, "medium")

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.effort, "high")
    }

    func testApplyPermissionModeChangeReconfiguresWhenProcessIsNotRunning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.permissionMode, "acceptEdits")
    }

    func testApplyModelChangeReconfiguresWhenProcessIsNotRunning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "opus")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.model, "opus")
    }

    func testApplyEffortChangeSkipsReconfigureBeforeInitialSetup() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyEffortChangeIsRejectedDuringActiveTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "medium")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyPermissionModeChangeIsRejectedDuringActiveTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyModelChangeIsRejectedDuringActiveTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        try fixture.dbThread().model = "sonnet"
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "sonnet")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyEffortChangeIsRejectedWhileSendingMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.viewModel.state.isSendingMessage = true

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "medium")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyEffortChangeRollsBackOnReconfigureFailure() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: false
        )

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "medium")
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    func testApplyModelChangeRollsBackOnReconfigureFailure() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "sonnet"
        try fixture.context.save()

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "sonnet")
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    func testApplyPermissionModeChangeRollsBackOnReconfigureFailure() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.showPermissionBanner = true
        fixture.viewModel.state.lastPermissionDeniedToolNames = ["Edit"]

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertTrue(fixture.viewModel.state.showPermissionBanner)
        XCTAssertEqual(fixture.viewModel.state.lastPermissionDeniedToolNames, ["Edit"])
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    // A concurrent fork attempt (`isReconfiguringSession` already set) must
    // drop at `reconfigureSession`'s inner guard. The composer disables the
    // picker in `.progressOnly(.reconfiguringSession)` mode so users can't
    // reach this in practice, but the guard covers programmatic writes.
    func testApplyEffortChangeSkipsReconfigureWhileAlreadyReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        fixture.viewModel.state.isReconfiguringSession = true

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyModelChangeSkipsReconfigureWhileAlreadyReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        fixture.viewModel.state.isReconfiguringSession = true

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "opus")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyWorktreePreferenceChangePersistsWhenProjectIsGitRepository() async throws {
        let fixture = try ConversationViewModelTestFixture(
            useWorktree: false,
            hasCompletedInitialSetup: false
        )

        fixture.viewModel.applyWorktreePreferenceChange(true)

        XCTAssertTrue(try fixture.dbThread().useWorktree)
    }

    func testApplyWorktreePreferenceChangeIgnoresNonGitProjects() async throws {
        let fixture = try ConversationViewModelTestFixture(
            useWorktree: false,
            hasCompletedInitialSetup: false,
            projectIsGitRepository: false
        )

        fixture.viewModel.applyWorktreePreferenceChange(true)

        XCTAssertFalse(try fixture.dbThread().useWorktree)
    }

    // Local vs. worktree is a first-setup choice. Once the thread has sent its
    // first message (`hasCompletedInitialSetup == true`) the picker is hidden,
    // but the handler must also refuse programmatic writes as a defense-in-depth
    // guard so a stray binding write can't repoint a live thread.
    func testApplyWorktreePreferenceChangeIsRejectedAfterInitialSetup() async throws {
        let fixture = try ConversationViewModelTestFixture(
            useWorktree: false,
            hasCompletedInitialSetup: true
        )

        fixture.viewModel.applyWorktreePreferenceChange(true)

        XCTAssertFalse(try fixture.dbThread().useWorktree)
    }

    // The sync prologue (state + DB mutation) must run before the returned Task
    // is observable, so SwiftUI's next render sees the new value on the same
    // cycle as the click. Await of the returned Task would only add the async
    // fork tail; the DB write must already be visible without awaiting.
    func testApplyEffortChangePersistsBeforeReturning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )

        let task = fixture.viewModel.applyEffortChange("high")
        XCTAssertEqual(try fixture.dbThread().effort, "high")

        await task.value
    }

    func testApplyModelChangePersistsBeforeReturning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )

        let task = fixture.viewModel.applyModelChange("opus")
        XCTAssertEqual(try fixture.dbThread().model, "opus")

        await task.value
    }

    func testApplyWorktreePreferenceChangeIsRejectedWhileSendingMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(
            useWorktree: false,
            hasCompletedInitialSetup: false
        )
        fixture.viewModel.state.isSendingMessage = true

        fixture.viewModel.applyWorktreePreferenceChange(true)

        XCTAssertFalse(try fixture.dbThread().useWorktree)
    }
}
