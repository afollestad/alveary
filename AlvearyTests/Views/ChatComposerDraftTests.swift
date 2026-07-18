import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerDraftTests: XCTestCase {
    func testLegacyDraftSendsStoredTextDirectly() {
        let draft = ComposerDraft(
            text: "Please read @/tmp/alveary/project/My%20Notes.md",
            source: .legacyText
        )

        XCTAssertEqual(
            draft.messageText,
            "Please read @/tmp/alveary/project/My%20Notes.md"
        )
    }

    func testBlockInputMarkdownDraftSendsMarkdownDirectly() {
        let markdown = "Please read [My Notes](/tmp/alveary/project/My%20Notes.md)"
        let draft = ComposerDraft(text: markdown, source: .blockInputMarkdown)

        XCTAssertEqual(draft.messageText, markdown)
    }

    func testBlockInputMarkdownDraftUsesBlockInputEmptinessForEmptyCodeBlock() {
        let markdown = "```\n```"
        let draft = ComposerDraft(text: markdown, source: .blockInputMarkdown)

        XCTAssertTrue(ChatComposerTextSupport.isEffectivelyEmpty(markdown))
        XCTAssertFalse(draft.isEffectivelyEmpty)
    }

    func testVoiceShortcutRemainsEnabledToStopWhenBaseComposerBecomesUnavailable() throws {
        #if arch(arm64)
        let fixture = try ConversationViewModelTestFixture()
        let service = FakeChatVoiceInputService()
        let settings = InMemorySettingsService()
        let chatView = makeChatView(
            fixture: fixture,
            appState: AppState(),
            settingsService: settings,
            voiceInputService: service,
            voiceInputLifecycleController: VoiceInputLifecycleController(service: service)
        )
        XCTAssertFalse(chatView.isBaseVoiceInputComposerUsable)
        XCTAssertNotNil(chatView.voiceInputShortcutAvailability.descriptor)

        chatView.voiceInputCoordinator.phase = .recording

        XCTAssertTrue(chatView.voiceInputShortcutConfiguration.isEnabled)
        #endif
    }

    func testSendDraftClearsDraftAndRequestsComposerFocus() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("Hello from BlockInput", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected submitted draft to send") {
            await fixture.agentsManager.sentMessages() == ["Hello from BlockInput"]
        }
    }

    func testSteerDraftClearsDraftAndRequestsComposerFocus() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.replaceInputDraft("Steer the current turn", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.steerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected steering draft to send") {
            await fixture.agentsManager.sentMessages() == ["Steer the current turn"]
        }
    }

    func testAlternateSteerDraftWithNonEmptyDraftSteersCurrentTurn() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.replaceInputDraft("Steer via shortcut", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected alternate steering draft to send") {
            await fixture.agentsManager.sentMessages() == ["Steer via shortcut"]
        }
    }

    func testAlternateSteerDraftWithEmptyDraftSteersNextQueuedMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.stagedContext = "Queued context"
        try await fixture.viewModel.queueOrSend("Queued steer")
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected queued message to steer") {
            await fixture.agentsManager.sentMessages() == ["Queued context\n\nQueued steer"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }
    }

    func testAlternateSteerDraftDuringSessionHandoffLeavesQueuedMessageParked() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.messageQueue.enqueue("Queued steer", stagedContext: "Queued context")
        fixture.viewModel.state.isHandingOffSession = true
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(appState.pendingComposerFocusToken)
        try await Task.sleep(nanoseconds: 50_000_000)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Queued steer"])
    }

    func testAlternateSteerDraftDuringSessionHandoffDoesNotClearDraft() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isHandingOffSession = true
        fixture.viewModel.replaceInputDraft("Do not steer during handoff", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Do not steer during handoff")
        XCTAssertNil(appState.pendingComposerFocusToken)
        try await Task.sleep(nanoseconds: 50_000_000)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testSteerDraftDuringSessionHandoffDoesNotClearDraft() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isHandingOffSession = true
        fixture.viewModel.replaceInputDraft("Do not steer directly during handoff", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.steerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Do not steer directly during handoff")
        XCTAssertNil(appState.pendingComposerFocusToken)
        try await Task.sleep(nanoseconds: 50_000_000)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testQueuedMessagesConfigurationDisablesSteerDuringSessionHandoff() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.messageQueue.enqueue("Queued steer", stagedContext: nil)
        fixture.viewModel.state.isHandingOffSession = true
        let chatView = makeChatView(fixture: fixture, appState: appState)

        let configuration = try XCTUnwrap(chatView.composerQueuedMessagesConfiguration)

        XCTAssertTrue(configuration.supportsMidTurnSteering)
        XCTAssertFalse(configuration.isTurnActive)
        XCTAssertNil(configuration.inFlightQueuedMessageID)
        XCTAssertEqual(configuration.queuedMessages.map(\.text), ["Queued steer"])
    }

    func testAlternateSteerDraftWithEmptyDraftAndNoQueueDoesNothing() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(appState.pendingComposerFocusToken)
        try await Task.sleep(nanoseconds: 50_000_000)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testTrustBlockedAlternateSteerDraftDoesNotClearOrRequestComposerFocus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.replaceInputDraft("Do not steer while blocked", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, isProjectTrustBlocked: true)

        chatView.alternateSteerDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Do not steer while blocked")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func testHandoffSteeringSubmitRequestsComposerFocusAfterClear() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.isAwaitingHandoffSteering = true
        fixture.viewModel.replaceInputDraft("Keep the next session concise", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.submittedHandoffSteeringPrompt, "Keep the next session concise")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected hidden handoff send to start") {
            await fixture.agentsManager.sentMessages().count == 1
        }
    }

    func testHandoffSteeringSubmitDoesNotTreatSlashTextAsLocalCommand() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.isAwaitingHandoffSteering = true
        fixture.viewModel.replaceInputDraft("/handoff keep the next session concise", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsPlanMode: true)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(
            fixture.viewModel.state.submittedHandoffSteeringPrompt,
            "/handoff keep the next session concise"
        )
        try await waitUntil("expected slash-looking steering prompt to start hidden handoff") {
            await fixture.agentsManager.sentMessages().count == 1
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testHandoffSteeringCountdownAppearsInComposerPrimaryActionTitle() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.isAwaitingHandoffSteering = true
        fixture.viewModel.state.handoffSteeringCountdownRemaining = 7
        let chatView = makeChatView(fixture: fixture, appState: appState)

        XCTAssertEqual(chatView.composerActionRowConfiguration.primaryActionTitle, "Submit (7)")
    }

    func testSessionHandoffOutputSendDoesNotTreatSlashTextAsLocalCommand() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.pendingHandoffOutput = "/plan carry this context forward"
        fixture.viewModel.replaceInputDraft("/plan carry this context forward", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsPlanMode: true)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        try await waitUntil("expected slash-looking handoff output to send") {
            await fixture.agentsManager.sentMessages() == ["/plan carry this context forward"]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
    }

    func testFastCommandWithArgumentEnablesFastAndSendsPrompt() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.runtimeSpeedMode = .standard
        fixture.viewModel.replaceInputDraft("/fast Fix the tests", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            supportsSpeedMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected fast command prompt to send") {
            await fixture.agentsManager.sentMessages() == ["Fix the tests"]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertEqual(reconfigureCalls.first?.config.speedMode, .fast)
        XCTAssertEqual(try fixture.dbThread().normalizedSpeedMode, .fast)
    }

    func testCompactCommandSendsAsNormalText() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/compact focus on recent work", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            supportsPlanMode: true,
            supportsSpeedMode: true,
            providerID: "claude"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected compact command to send as user text") {
            await fixture.agentsManager.sentMessages() == ["/compact focus on recent work"]
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testCompactCommandQueuesAsNormalVisibleMessageWhileBusy() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        let appState = AppState()
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.replaceInputDraft("/compact", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, providerID: "claude")

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        try await waitUntil("expected compact command to queue as visible text") {
            fixture.viewModel.messageQueue.pending.map(\.text) == ["/compact"]
        }
        XCTAssertNotNil(appState.pendingComposerFocusToken)
    }

    func testLocalHandoffCommandAvailabilityDoesNotDependOnAutomaticHandoffSetting() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.settingsService.update {
            $0.contextManagementEnabled = false
        }
        let chatView = makeChatView(fixture: fixture, appState: appState)

        let availability = chatView.localCommandAvailability

        XCTAssertTrue(availability.supportsSessionHandoff)
        XCTAssertEqual(
            ComposerLocalCommandParser.parse("/handoff Focus on the next session.", availability: availability),
            ComposerLocalCommand(kind: .handoff, argument: "Focus on the next session.")
        )
    }

    func testCompactPassthroughCommandAvailabilityIsClaudeOnlyOutsideHandoff() throws {
        let claudeFixture = try ConversationViewModelTestFixture(providerId: "claude")
        let appState = AppState()
        let claudeView = makeChatView(fixture: claudeFixture, appState: appState, providerID: "claude")
        XCTAssertEqual(claudeView.passthroughSlashCommands.map(\.command), ["compact"])

        let codexFixture = try ConversationViewModelTestFixture(providerId: "codex")
        let codexView = makeChatView(fixture: codexFixture, appState: appState, providerID: "codex")
        XCTAssertTrue(codexView.passthroughSlashCommands.isEmpty)

        claudeFixture.viewModel.state.isAwaitingHandoffSteering = true
        XCTAssertTrue(claudeView.passthroughSlashCommands.isEmpty)
    }

    func testEmptySendDraftDoesNotRequestComposerFocus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func testTrustBlockedSendDraftDoesNotClearOrRequestComposerFocus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("Do not send while blocked", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, isProjectTrustBlocked: true)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Do not send while blocked")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func testInFlightSendDraftDoesNotClearOrRequestComposerFocus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.isSendingMessage = true
        fixture.viewModel.replaceInputDraft("Already sending", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Already sending")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func makeChatView(
        fixture: ConversationViewModelTestFixture,
        appState: AppState,
        isProjectTrustBlocked: Bool = false,
        supportsGoalMode: Bool = false,
        supportsExistingSessionGoalStart: Bool = false,
        supportsPlanMode: Bool = false,
        supportsSpeedMode: Bool = false,
        supportsLocalImageInput: Bool = false,
        effortOptions: [ChatComposerActionRowView.MenuOption] = [],
        selectedEffort: String = AppSettings.defaultEffortLevel,
        onEffortChange: @escaping (String) -> Bool = { _ in true },
        providerID: String = "claude",
        settingsService: SettingsService? = nil,
        voiceInputService: (any VoiceInputService)? = nil,
        voiceInputLifecycleController: VoiceInputLifecycleController? = nil
    ) -> ChatView {
        ChatView(
            viewModel: fixture.viewModel,
            conversation: fixture.conversation,
            composerCapabilities: ComposerCapabilities(
                supportedPermissionModes: [],
                supportsMidTurnSteering: true,
                supportsGoalMode: supportsGoalMode,
                supportsExistingSessionGoalStart: supportsExistingSessionGoalStart,
                supportsPlanMode: supportsPlanMode,
                supportsSpeedMode: supportsSpeedMode,
                supportsLocalImageInput: supportsLocalImageInput
            ),
            reasoningConfiguration: makeReasoningConfiguration(
                modelOptions: [
                    .init(
                        value: AppSettings.defaultModelValue,
                        title: ChatComposerTextSupport.modelLabel(for: AppSettings.defaultModelValue)
                    )
                ],
                effortOptions: effortOptions,
                selectedModel: AppSettings.defaultModelValue,
                selectedEffort: selectedEffort,
                onEffortChange: onEffortChange
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
            settingsService: settingsService,
            voiceInputService: voiceInputService,
            voiceInputLifecycleController: voiceInputLifecycleController,
            transcriptTypography: TranscriptTypography(),
            appState: appState
        )
    }

    func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let pngHeaderData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
