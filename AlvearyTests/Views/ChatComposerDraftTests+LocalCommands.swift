import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testBareEffortCommandClearsOnlyTextWithoutSendingOrRequestingComposerFocus() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        let attachment = LocalFileAttachment(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        )
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        fixture.viewModel.replaceInputDraft("/effort", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            providerID: "codex"
        )

        chatView.sendDraft()

        let request = try XCTUnwrap(chatView.reasoningMenuRequestState.pendingRequest)
        XCTAssertEqual(chatView.composerActionRowConfiguration.reasoningMenuPresentationRequest, request)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [attachment])
        XCTAssertNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testEffortCommandWithTrailingSpaceClearsOnlyTextWithoutSendingOrRequestingComposerFocus() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        let attachment = LocalFileAttachment(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        )
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        fixture.viewModel.replaceInputDraft("/effort ", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            providerID: "codex"
        )

        chatView.sendDraft()

        let request = try XCTUnwrap(chatView.reasoningMenuRequestState.pendingRequest)
        XCTAssertEqual(chatView.composerActionRowConfiguration.reasoningMenuPresentationRequest, request)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [attachment])
        XCTAssertNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testEffortCommandAppliesCanonicalCaseInsensitiveValueWithoutSending() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        var appliedEfforts: [String] = []
        fixture.viewModel.replaceInputDraft("/effort HIGH", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { effort in
                appliedEfforts.append(effort)
                return true
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(appliedEfforts, ["high"])
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testEffortCommandStagesAcceptedValueDuringActiveTurnWithoutSteeringOrQueueing() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.replaceInputDraft("/effort high", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { effort in
                _ = fixture.viewModel.applyEffortChange(effort)
                return fixture.conversation.thread?.effort == effort
            },
            providerID: "codex"
        )

        chatView.steerDraft()

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertEqual(fixture.viewModel.state.pendingSessionSettingsChange?.pending.effort, "high")
        XCTAssertTrue(fixture.viewModel.messageQueue.pending.isEmpty)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

    func testEffortCommandPersistsBeforeStartWithoutSpawning() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/effort high", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { effort in
                _ = fixture.viewModel.applyEffortChange(effort)
                return fixture.conversation.thread?.effort == effort
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(try fixture.dbThread().effort, "high")
        XCTAssertFalse(try fixture.dbThread().hasCompletedInitialSetup)
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testInvalidEffortCommandPreservesDraftAttachmentsAndShowsDynamicError() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        let attachment = LocalFileAttachment(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        )
        var appliedEfforts: [String] = []
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        fixture.viewModel.replaceInputDraft("/effort high with extras", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { effort in
                appliedEfforts.append(effort)
                return true
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertTrue(appliedEfforts.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/effort high with extras")
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [attachment])
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Effort must be one of: low|medium|high|xhigh.")
        XCTAssertNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testRejectedEffortCommandPreservesDraftAndUnderlyingError() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/effort high", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { _ in
                fixture.viewModel.lastTurnError = "Could not save the setting."
                return false
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/effort high")
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Could not save the setting.")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func testRejectedEffortCommandUsesFallbackErrorWhenCallbackProvidesNone() throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/effort high", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            effortOptions: effortMenuOptions,
            onEffortChange: { _ in false },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/effort high")
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Effort cannot be changed right now.")
        XCTAssertNil(appState.pendingComposerFocusToken)
    }

    func testEffortTextIsNotInterceptedWithoutModelEffortOptions() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/effort high", source: .blockInputMarkdown)
        let chatView = makeChatView(fixture: fixture, appState: appState, providerID: "codex")

        chatView.sendDraft()

        try await waitUntil("expected unsupported effort command text to pass through") {
            await fixture.agentsManager.sentMessages() == ["/effort high"]
        }
    }

    func testFastCommandFailureRestoresStagedAppShotAttachment() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let screenshotURL = root.appendingPathComponent("appshot.png")
        try Self.pngHeaderData.write(to: screenshotURL)
        let screenshot = LocalImageAttachment(
            id: "appshot-image",
            fileURL: screenshotURL,
            label: "appshot.png",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let appShot = AppShotAttachment(
            id: "appshot",
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Preview - Document.pdf",
            screenshot: screenshot,
            axTreeText: "AX tree",
            focusedElementSummary: "",
            attachmentStoreRoot: root
        )
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))
        fixture.viewModel.state.runtimeSpeedMode = .standard
        fixture.viewModel.state.stagedAppShots = [appShot]
        fixture.viewModel.replaceInputDraft("/fast Fix the tests", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            supportsSpeedMode: true,
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertNotNil(appState.pendingComposerFocusToken)
        try await waitUntil("expected fast command send failure") {
            fixture.viewModel.lastTurnError != nil
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Fix the tests")
        XCTAssertEqual(fixture.viewModel.state.stagedAppShots, [appShot])
    }

    private var effortMenuOptions: [ChatComposerActionRowView.MenuOption] {
        [
            .init(value: "low", title: "Low"),
            .init(value: "medium", title: "Medium"),
            .init(value: "high", title: "High"),
            .init(value: "xhigh", title: "Extra High")
        ]
    }
}
