import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
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

    func testApplyModelChangeInvalidatesContextWindowAfterSuccessfulReconfigure() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )

        await fixture.viewModel.applyModelChange("opus").value

        let invalidations = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.contextWindowInvalidatedType
        }
        XCTAssertEqual(invalidations.count, 1)
        XCTAssertEqual(invalidations.first?.conversationId, fixture.conversation.id)
    }

    func testApplyModelChangeDoesNotInvalidateContextWindowWhenReconfigureFails() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            reconfigureError: .reconfigureFailed,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "sonnet"
        try fixture.context.save()

        await fixture.viewModel.applyModelChange("opus").value

        let invalidations = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.contextWindowInvalidatedType
        }
        XCTAssertTrue(invalidations.isEmpty)
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

    func testApplyEffortChangeIsRejectedWhileRuntimeBusy() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

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

    func testApplyPermissionModeChangeIsRejectedDuringPendingToolApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: ToolApprovalRequest(
                sessionId: "session-123",
                toolUseId: "tool-1",
                toolName: "Bash",
                toolInput: "{\"command\":\"swift test\"}"
            ),
            status: .pending
        )

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyPermissionModeChangeIsRejectedWhilePromptIsUnanswered() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.viewModel.state.grouper.append(event: promptRecord)

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

    // Opus 4.8-only efforts (currently `xhigh`) must fall back to the default
    // when the user switches to a model that does not accept them; otherwise
    // the next spawn would pass a flag the CLI rejects.
    func testApplyModelChangeResetsEffortWhenNewModelDoesNotSupportIt() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.dbThread().effort = "xhigh"
        try fixture.context.save()

        await fixture.viewModel.applyModelChange("sonnet").value

        XCTAssertEqual(try fixture.dbThread().model, "sonnet")
        XCTAssertEqual(try fixture.dbThread().effort, AppSettings.defaultEffortLevel)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.effort, AppSettings.defaultEffortLevel)
    }

    func testApplyModelChangePreservesEffortWhenNewModelStillSupportsIt() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "sonnet"
        try fixture.dbThread().effort = "high"
        try fixture.context.save()

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertEqual(try fixture.dbThread().model, "opus")
        XCTAssertEqual(try fixture.dbThread().effort, "high")
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

        await fixture.viewModel.applyPermissionModeChange("acceptEdits").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    func testApplyPermissionModeChangeTracksPreviousNonPlanModeWhenEnteringPlan() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()

        await fixture.viewModel.applyPermissionModeChange("plan").value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.lastNonPlanPermissionMode, "acceptEdits")
    }

    func testRuntimePermissionModeChangePersistsLiveModeToThread() throws {
        let fixture = try ConversationViewModelTestFixture()
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()

        fixture.viewModel.handleEvent(.permissionModeChanged("plan"))

        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "plan")
        XCTAssertEqual(fixture.viewModel.state.lastNonPlanPermissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "plan")
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
