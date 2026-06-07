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

    private func makeChatView(
        fixture: ConversationViewModelTestFixture,
        appState: AppState,
        isProjectTrustBlocked: Bool = false
    ) -> ChatView {
        ChatView(
            viewModel: fixture.viewModel,
            conversation: fixture.conversation,
            composerCapabilities: ComposerCapabilities(
                supportedPermissionModes: [],
                supportsMidTurnSteering: true
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
            providerID: "claude",
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
}
