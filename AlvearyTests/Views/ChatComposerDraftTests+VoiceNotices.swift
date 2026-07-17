import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testVoiceNoticeAppearsBetweenLastTurnErrorAndSessionContinuityNotice() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.lastTurnError = "Turn failed."
        fixture.viewModel.sessionContinuityNotice = "Session changed."
        fixture.viewModel.state.stagedContext = "Staged context"
        let chatView = makeChatView(fixture: fixture, appState: AppState())
        chatView.voiceInputCoordinator.notice = ChatVoiceInputNotice(
            message: "Voice input failed.",
            severity: .error,
            recovery: nil
        )

        let labels = chatView.composerTopContentConfiguration.items.map { item in
            switch item {
            case .inlineBanner(let configuration):
                configuration.message
            case .goalStatus:
                "goal"
            case .stagedContext(let configuration):
                configuration.context
            }
        }

        XCTAssertEqual(labels, ["Turn failed.", "Voice input failed.", "Session changed.", "Staged context"])
    }

    func testRuntimeVoiceNoticeDismissalIsExposedByBanner() throws {
        let fixture = try ConversationViewModelTestFixture()
        let chatView = makeChatView(fixture: fixture, appState: AppState())
        chatView.voiceInputCoordinator.notice = ChatVoiceInputNotice(
            message: "Dictation stopped because audio processing could not keep up.",
            severity: .error,
            recovery: nil
        )

        let banner = try XCTUnwrap(inlineBanner(in: chatView.composerTopContentConfiguration))

        XCTAssertNil(banner.actionTitle)
        XCTAssertNil(banner.onAction)
        XCTAssertNotNil(banner.onDismiss)
        banner.onDismiss?()
        XCTAssertNil(chatView.voiceInputCoordinator.notice)
    }

    func testPreparingVoiceModelUsesModalInsteadOfComposerBanner() throws {
        let fixture = try ConversationViewModelTestFixture()
        let chatView = makeChatView(fixture: fixture, appState: AppState())
        chatView.voiceInputCoordinator.phase = .preparing(message: "Downloading voice model…", fraction: 0.424)
        chatView.voiceInputCoordinator.modelModalState = .preparing(
            .downloading(kind: .installation, fraction: 0.424)
        )

        XCTAssertNil(inlineBanner(in: chatView.composerTopContentConfiguration))
        let modal = try XCTUnwrap(chatView.chatWindowModal)
        XCTAssertEqual(modal.id, "voice-input-model-preparation")
        switch modal.dismissPolicy {
        case .nonDismissible:
            break
        case .dismissible:
            XCTFail("Voice model preparation must not be dismissible through the shared modal container.")
        }
    }

    func testVoiceModelModalHasPriorityOverPausedQueueAndCannotDismissIt() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let appState = AppState()
        fixture.viewModel.state.messageQueue.enqueue("Queued one", stagedContext: nil)
        fixture.viewModel.state.queuedMessagesPauseReason = .interrupted
        fixture.viewModel.replaceInputDraft("Send this now", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState)

        chatView.sendDraft()
        XCTAssertNotNil(chatView.pausedQueueSendModal)

        chatView.voiceInputCoordinator.modelModalState = .preparing(.checkingModel)
        let voiceModal = try XCTUnwrap(chatView.chatWindowModal)
        XCTAssertEqual(voiceModal.id, "voice-input-model-preparation")

        chatView.dismissChatWindowModal()

        XCTAssertNotNil(fixture.viewModel.state.pausedQueueSendConfirmation)
        XCTAssertEqual(chatView.chatWindowModal?.id, "voice-input-model-preparation")

        chatView.voiceInputCoordinator.modelModalState = nil
        XCTAssertTrue(try XCTUnwrap(chatView.chatWindowModal).id.hasPrefix("paused-queue-send-"))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    private func inlineBanner(
        in configuration: AppKitChatComposerTopContentView.Configuration
    ) -> AppKitChatComposerTopContentView.InlineBannerConfiguration? {
        configuration.items.lazy.compactMap { item in
            guard case .inlineBanner(let banner) = item else {
                return nil
            }
            return banner
        }.first
    }
}
