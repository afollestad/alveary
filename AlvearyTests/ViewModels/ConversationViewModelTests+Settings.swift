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

        await fixture.viewModel.applyModelChange(
            "sonnet",
            effortOptions: AgentModelOptionTestFixtures.claudeDefaultEfforts,
            defaultEffort: AgentModelOptionTestFixtures.medium.value
        ).value

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

        await fixture.viewModel.applyModelChange(
            "opus",
            effortOptions: AgentModelOptionTestFixtures.claudeOpusEfforts,
            defaultEffort: AgentModelOptionTestFixtures.xhigh.value
        ).value

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

    func testApplyProviderChangeBeforeInitialSetupUpdatesThreadDefaults() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = true
        try fixture.dbThread().effort = "high"
        try fixture.context.save()

        fixture.viewModel.applyProviderChange("codex")

        XCTAssertEqual(try fixture.dbConversation().provider, "codex")
        XCTAssertNil(try fixture.dbThread().model)
        XCTAssertEqual(try fixture.dbThread().permissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
        XCTAssertEqual(try fixture.dbThread().effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
        XCTAssertEqual(fixture.viewModel.state.lastNonPlanPermissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
    }

    func testApplyProviderChangeIsRejectedAfterInitialSetup() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()

        fixture.viewModel.applyProviderChange("codex")

        XCTAssertEqual(try fixture.dbConversation().provider, "claude")
        XCTAssertEqual(try fixture.dbThread().model, "opus")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
    }

    func testApplyPreStartupProviderModelChangeSavesProviderModelPermissionPlanAndPreservesSupportedEffort() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = true
        try fixture.dbThread().effort = "high"
        try fixture.context.save()

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "codex",
            model: "gpt-5.5",
            effortOptions: AgentModelOptionTestFixtures.codexDefaultEfforts,
            defaultEffort: AgentModelOptionTestFixtures.medium.value
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(try fixture.dbConversation().provider, "codex")
        XCTAssertEqual(try fixture.dbThread().model, "gpt-5.5")
        XCTAssertEqual(try fixture.dbThread().permissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, AppSettings.defaultPermissionMode(forProvider: "codex"))
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
    }

    func testApplyPreStartupProviderModelChangeDefaultsUnsupportedEffortAndKeepsDefaultModelSentinel() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.dbThread().effort = "max"
        try fixture.context.save()

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "codex",
            model: AppSettings.defaultModelValue,
            effortOptions: AgentModelOptionTestFixtures.codexDefaultEfforts,
            defaultEffort: AgentModelOptionTestFixtures.medium.value
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(try fixture.dbConversation().provider, "codex")
        XCTAssertNil(try fixture.dbThread().model)
        XCTAssertEqual(try fixture.dbThread().effort, "medium")
    }

    func testApplyPreStartupProviderModelChangeIsRejectedAfterInitialSetup() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().model = "opus"
        try fixture.context.save()

        let didApply = fixture.viewModel.applyPreStartupProviderModelChange(
            providerID: "codex",
            model: "gpt-5.5",
            effortOptions: AgentModelOptionTestFixtures.codexDefaultEfforts,
            defaultEffort: AgentModelOptionTestFixtures.medium.value
        )

        XCTAssertFalse(didApply)
        XCTAssertEqual(try fixture.dbConversation().provider, "claude")
        XCTAssertEqual(try fixture.dbThread().model, "opus")
    }

    func testNewThreadSpawnConfigCarriesPlanMode() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()

        await fixture.viewModel.applyPlanModeChange(true).value
        let config = try fixture.viewModel.makeSpawnConfig()

        XCTAssertEqual(config.permissionMode, "acceptEdits")
        XCTAssertEqual(config.planModeEnabled, true)
    }

    func testApplyPlanModeChangeKeepsPreviousNonPlanPermissionMode() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()

        await fixture.viewModel.applyPlanModeChange(true).value

        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.lastNonPlanPermissionMode, "acceptEdits")
    }

    func testApplyPlanModeChangeReconfiguresIdleThread() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.context.save()

        await fixture.viewModel.applyPlanModeChange(true).value

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.count, 1)
        XCTAssertEqual(reconfigureCalls.first?.config.permissionMode, "acceptEdits")
        XCTAssertEqual(reconfigureCalls.first?.config.planModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.liveSessionConfig?.planModeEnabled, true)
        XCTAssertNil(fixture.viewModel.state.pendingSessionSettingsChange)
    }

    func testRuntimePermissionModeChangePersistsLiveModeToThread() throws {
        let fixture = try ConversationViewModelTestFixture()
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()

        fixture.viewModel.handleEvent(.permissionModeChanged("plan"))

        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "default")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, true)
        XCTAssertEqual(fixture.viewModel.state.lastNonPlanPermissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, true)
    }

    func testApplyEffortChangeIsRejectedWhileAlreadyReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        fixture.viewModel.state.isReconfiguringSession = true

        await fixture.viewModel.applyEffortChange("high").value

        XCTAssertEqual(try fixture.dbThread().effort, "medium")
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testApplyModelChangeIsRejectedWhileAlreadyReconfiguring() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        fixture.viewModel.state.isReconfiguringSession = true

        await fixture.viewModel.applyModelChange("opus").value

        XCTAssertNil(try fixture.dbThread().model)
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
