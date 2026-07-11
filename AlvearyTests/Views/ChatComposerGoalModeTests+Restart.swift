import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerGoalModeTests {
    func testGoalResumeCommandRoutesProviderResumeForPausedGoal() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .paused, availableActions: [.resume, .delete])
        fixture.viewModel.replaceInputDraft("/goal resume", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        try await waitUntil("expected exact goal resume to perform resume") {
            await fixture.agentsManager.goalActionCalls().map(\.action) == [.resume]
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
    }

    func testGoalResumeCommandRestartsBlockedGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        fixture.viewModel.replaceInputDraft("/goal resume", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: appState,
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Current goal")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
        XCTAssertNotNil(appState.pendingComposerFocusToken)
    }

    func testGoalRestartCommandReportsNoBlockedGoalForActiveGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartActiveGoal()
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "No blocked goal is available to restart.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandReportsNoBlockedGoalForPausedGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .paused, availableActions: [.resume])
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "No blocked goal is available to restart.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandReportsNoBlockedGoalForAchievedGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .achieved)
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "No blocked goal is available to restart.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandReportsNoBlockedGoalWithoutVisibleGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "No blocked goal is available to restart.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalResumeCommandOnAchievedGoalUsesProviderActionHandling() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .achieved)
        fixture.viewModel.replaceInputDraft("/goal resume", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        try await waitUntil("expected achieved goal resume to report no active goal") {
            fixture.viewModel.state.goalActionError == "No active goal is available."
        }
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalResumeCommandWithoutActiveGoalUsesProviderActionHandling() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.replaceInputDraft("/goal resume", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        try await waitUntil("expected missing goal resume to report no active goal") {
            fixture.viewModel.state.goalActionError == "No active goal is available."
        }
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandDoesNotUseDismissedTerminalGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let blocked = restartGoal(status: .blocked)
        fixture.viewModel.state.goalSnapshot = blocked
        fixture.viewModel.state.dismissedTerminalGoalKeys.insert(blocked.stableGoalKey)
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "No blocked goal is available to restart.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandUnavailableWhileProjectTrustBlocked() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex",
            isProjectTrustBlocked: true
        )

        _ = chatView.handleComposerGoalOrLocalControlIfNeeded(draft: ComposerDraft(
            text: "/goal restart",
            source: .blockInputMarkdown,
            isEffectivelyEmpty: false
        ))

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "Approve this project before starting Goal mode.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testGoalRestartCommandWhileAlreadyArmedPreservesDraft() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: appState,
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/goal restart")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
    }

    func testGoalRestartCommandRestartsUsageLimitedGoal() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .usageLimited)
        fixture.viewModel.replaceInputDraft("/goal restart", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Current goal")
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
    }

    func testGoalRestartCommandWithExtraTextStartsGoalObjective() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.replaceInputDraft("/goal restart flaky tests", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        try await waitUntil("expected goal restart text to start a goal objective") {
            await fixture.agentsManager.goalStartCalls().map(\.initialGoal) == ["restart flaky tests"]
        }
        let goalActionCalls = await fixture.agentsManager.goalActionCalls()
        XCTAssertTrue(goalActionCalls.isEmpty)
    }

    func testBlockedGoalRowRestartArmsGoalModeAndPrefillsEmptyDraft() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        try fixture.dbThread().planModeEnabled = true
        try fixture.context.save()
        fixture.viewModel.state.goalActionError = "Old error"
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: appState,
            supportsGoalMode: true,
            supportsPlanMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)
        XCTAssertNotNil(goalConfiguration.onRestartTerminal)
        XCTAssertTrue(goalConfiguration.isRestartTerminalEnabled)
        XCTAssertNil(goalConfiguration.restartTerminalDisabledTooltip)

        goalConfiguration.onRestartTerminal?()

        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Current goal")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .legacyText)
        XCTAssertFalse(fixture.viewModel.effectivePlanModeEnabled)
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
        XCTAssertNil(fixture.viewModel.state.goalActionError)
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        XCTAssertTrue(chatView.composerActionRowConfiguration.isGoalModeChipVisible)
    }

    func testBlockedGoalRowRestartPreservesNonEmptyDraft() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        fixture.viewModel.replaceInputDraft("Use this instead", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)
        goalConfiguration.onRestartTerminal?()

        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Use this instead")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
    }

    func testBlockedGoalRowRestartHiddenWhenGoalModeArmed() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        fixture.viewModel.state.isGoalModeArmed = true
        fixture.viewModel.replaceInputDraft("Current restart draft", source: .blockInputMarkdown)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)
        XCTAssertNil(goalConfiguration.onRestartTerminal)

        chatView.composerActionRowConfiguration.onGoalModeChipDismiss()

        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Current restart draft")
        XCTAssertEqual(fixture.viewModel.visibleGoalSnapshot?.status, .blocked)
    }

    func testBlockedGoalRowRestartUnavailableWhileProjectTrustBlocked() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex",
            isProjectTrustBlocked: true
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)
        XCTAssertNotNil(goalConfiguration.onRestartTerminal)
        XCTAssertFalse(goalConfiguration.isRestartTerminalEnabled)
        XCTAssertEqual(goalConfiguration.restartTerminalDisabledTooltip, "Approve this project before starting Goal mode.")

        goalConfiguration.onRestartTerminal?()

        XCTAssertEqual(fixture.viewModel.state.goalActionError, "Approve this project before starting Goal mode.")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testUsageLimitedGoalRowExposesRestart() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .usageLimited)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)

        XCTAssertNotNil(goalConfiguration.onRestartTerminal)
        XCTAssertTrue(goalConfiguration.isRestartTerminalEnabled)
    }

    func testAchievedGoalRowDoesNotExposeRestart() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .achieved)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)

        XCTAssertNil(goalConfiguration.onRestartTerminal)
        XCTAssertTrue(goalConfiguration.isRestartTerminalEnabled)
        XCTAssertNil(goalConfiguration.restartTerminalDisabledTooltip)
    }

    func testTerminalGoalRestartDoesNotCallGoalStartUntilSubmit() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        fixture.viewModel.state.goalSnapshot = restartGoal(status: .blocked)
        let chatView = makeRestartChatView(
            fixture: fixture,
            appState: AppState(),
            supportsGoalMode: true,
            providerID: "codex"
        )

        let goalConfiguration = try restartGoalStatusConfiguration(from: chatView)
        goalConfiguration.onRestartTerminal?()

        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        let existingGoalStarts = await fixture.agentsManager.existingGoalStartCalls()
        XCTAssertTrue(goalStartCalls.isEmpty)
        XCTAssertTrue(existingGoalStarts.isEmpty)
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
    }

    private func restartActiveGoal() -> AgentGoalSnapshot {
        restartGoal(status: .active, availableActions: [.delete])
    }

    private func restartGoal(
        status: AgentGoalStatus,
        availableActions: [AgentGoalAction] = []
    ) -> AgentGoalSnapshot {
        AgentGoalSnapshot(
            objective: "Current goal",
            status: status,
            availableActions: availableActions
        )
    }

    private func restartGoalStatusConfiguration(
        from chatView: ChatView
    ) throws -> AppKitChatComposerTopContentView.GoalStatusConfiguration {
        let item = try XCTUnwrap(chatView.composerTopContentConfiguration.items.first)
        guard case .goalStatus(let configuration) = item else {
            XCTFail("Expected goal status item.")
            throw RestartTestError.unexpectedGoalItem
        }
        return configuration
    }

    private func makeRestartChatView(
        fixture: ConversationViewModelTestFixture,
        appState: AppState,
        supportsGoalMode: Bool = false,
        supportsExistingSessionGoalStart: Bool = false,
        supportsPlanMode: Bool = false,
        providerID: String = "claude",
        isProjectTrustBlocked: Bool = false
    ) -> ChatView {
        ChatView(
            viewModel: fixture.viewModel,
            conversation: fixture.conversation,
            composerCapabilities: ComposerCapabilities(
                supportedPermissionModes: [],
                supportsMidTurnSteering: true,
                supportsGoalMode: supportsGoalMode,
                supportsExistingSessionGoalStart: supportsExistingSessionGoalStart,
                supportsPlanMode: supportsPlanMode
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
            isProjectTrustBlocked: isProjectTrustBlocked,
            onTrustProject: { _ in },
            onDenyProjectTrust: { _ in },
            loadFileCompletions: { [] },
            loadSkillCompletions: { [] },
            transcriptTypography: TranscriptTypography(),
            appState: appState
        )
    }

    private enum RestartTestError: Error {
        case unexpectedGoalItem
    }
}
