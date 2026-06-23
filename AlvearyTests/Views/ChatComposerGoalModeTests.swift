import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerGoalModeTests: XCTestCase {
    func testExactGoalClearRunsBeforeArmedGoalSubmitFromSendDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.goalSnapshot = activeGoal()
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("/goal clear", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsGoalMode: true, providerID: "codex")

        chatView.sendDraft()

        try await waitUntil("expected exact goal clear to perform the delete action") {
            await fixture.agentsManager.goalActionCalls().map(\.action) == [.delete]
        }
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        let existingGoalStarts = await fixture.agentsManager.existingGoalStartCalls()
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertTrue(goalStartCalls.isEmpty)
        XCTAssertTrue(existingGoalStarts.isEmpty)
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testExactGoalClearRunsBeforeArmedGoalSubmitFromSteerDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.goalSnapshot = activeGoal()
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("/goal clear", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsGoalMode: true, providerID: "codex")

        chatView.steerDraft()

        try await waitUntil("expected exact goal clear steer to perform the delete action") {
            await fixture.agentsManager.goalActionCalls().map(\.action) == [.delete]
        }
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertTrue(steeringCalls.isEmpty)
        XCTAssertTrue(goalStartCalls.isEmpty)
    }

    func testExactGoalClearRunsBeforeArmedGoalSubmitFromAlternateSteerDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.goalSnapshot = activeGoal()
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("/goal clear", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsGoalMode: true, providerID: "codex")

        chatView.alternateSteerDraft()

        try await waitUntil("expected exact goal clear alternate steer to perform the delete action") {
            await fixture.agentsManager.goalActionCalls().map(\.action) == [.delete]
        }
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertTrue(steeringCalls.isEmpty)
        XCTAssertTrue(goalStartCalls.isEmpty)
    }

    func testArmedGoalSubmitTreatsNonExactGoalClearTextAsObjective() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("/goal clear the logs", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsGoalMode: true, providerID: "codex")

        chatView.sendDraft()

        try await waitUntil("expected non-exact goal clear text to start a goal") {
            await fixture.agentsManager.goalStartCalls().map(\.initialGoal) == ["/goal clear the logs"]
        }
        let goalActionCalls = await fixture.agentsManager.goalActionCalls()
        XCTAssertTrue(goalActionCalls.isEmpty)
    }

    func testGoalActionCommandWithoutActiveGoalShowsGoalActionErrorOnly() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/goal pause", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsGoalMode: true, providerID: "codex")

        chatView.sendDraft()

        try await waitUntil("expected missing active goal to set action error") {
            fixture.viewModel.state.goalActionError == "No active goal is available."
        }
        let goalActionCalls = await fixture.agentsManager.goalActionCalls()
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(goalActionCalls.isEmpty)
        XCTAssertTrue(goalStartCalls.isEmpty)
    }

    func testEstablishedThreadGoalToggleRequiresExistingSessionCapability() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Earlier request",
            conversation: try fixture.dbConversation()
        ))
        try fixture.context.save()
        let unsupportedView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )
        let supportedView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            supportsExistingSessionGoalStart: true,
            providerID: "codex"
        )

        XCTAssertFalse(unsupportedView.isGoalModeToggleEnabled)
        XCTAssertEqual(
            unsupportedView.goalModeToggleDisabledTooltip,
            "This agent can only start Goal mode before the first visible user message."
        )
        XCTAssertTrue(supportedView.isGoalModeToggleEnabled)
        XCTAssertNil(supportedView.goalModeToggleDisabledTooltip)
    }

    func testTerminalGoalRowDoesNotDisableGoalToggle() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Previous goal",
            status: .achieved
        )
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        XCTAssertTrue(chatView.isGoalModeToggleEnabled)
        XCTAssertNil(chatView.goalModeToggleDisabledTooltip)
    }

    func testGoalChipShowsWhileArmedAndDisarmsComposer() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.isGoalModeArmed = true
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let configuration = chatView.composerActionRowConfiguration
        XCTAssertTrue(configuration.isGoalModeChipVisible)
        XCTAssertTrue(configuration.isGoalModeChipEnabled)

        configuration.onGoalModeChipDismiss()

        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalChipShowsForActiveGoalAndRoutesDeleteAction() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = activeGoal()
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let configuration = chatView.composerActionRowConfiguration
        XCTAssertTrue(configuration.isGoalModeChipVisible)
        XCTAssertTrue(configuration.isGoalModeChipEnabled)

        configuration.onGoalModeChipDismiss()

        try await waitUntil("expected goal chip dismiss to perform delete") {
            await fixture.agentsManager.goalActionCalls().map(\.action) == [.delete]
        }
    }

    func testGoalChipIsHiddenForTerminalGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Previous goal",
            status: .achieved
        )
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        XCTAssertFalse(chatView.composerActionRowConfiguration.isGoalModeChipVisible)
    }

    func testGoalChipIsHiddenWhenDeleteIsNotCurrentlyVisible() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        fixture.viewModel.state.goalSnapshot = activeGoal()
        fixture.viewModel.turnState.beginTurn()
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "claude"
        )

        let configuration = chatView.composerActionRowConfiguration
        XCTAssertFalse(configuration.isGoalModeChipVisible)
        XCTAssertFalse(configuration.isGoalModeChipEnabled)
    }

    private func activeGoal() -> AgentGoalSnapshot {
        AgentGoalSnapshot(
            objective: "Current goal",
            status: .active,
            availableActions: [.delete]
        )
    }

    private func makeChatView(
        fixture: ConversationViewModelTestFixture,
        appState: AppState,
        supportsGoalMode: Bool = false,
        supportsExistingSessionGoalStart: Bool = false,
        providerID: String = "claude"
    ) -> ChatView {
        ChatView(
            viewModel: fixture.viewModel,
            conversation: fixture.conversation,
            composerCapabilities: ComposerCapabilities(
                supportedPermissionModes: [],
                supportsMidTurnSteering: true,
                supportsGoalMode: supportsGoalMode,
                supportsExistingSessionGoalStart: supportsExistingSessionGoalStart
            ),
            reasoningConfiguration: makeReasoningConfiguration(
                modelOptions: [
                    .init(
                        value: AppSettings.defaultModelValue,
                        title: ChatComposerTextSupport.modelLabel(for: AppSettings.defaultModelValue)
                    )
                ],
                effortOptions: [],
                selectedModel: AppSettings.defaultModelValue
            ),
            defaultEnterBehavior: .queue,
            providerID: providerID,
            runtimeStatus: .neutral,
            contextWindowCache: fixture.contextWindowCache,
            workingDirectory: fixture.project.path,
            projectTrustPrompt: nil,
            isProjectTrustBlocked: false,
            onTrustProject: { _ in },
            onDenyProjectTrust: { _ in },
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            transcriptTypography: TranscriptTypography(),
            appState: appState
        )
    }
}
