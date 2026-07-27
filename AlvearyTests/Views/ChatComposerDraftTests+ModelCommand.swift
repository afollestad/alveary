import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testBareModelCommandOpensModelListWithoutSendingOrRequestingComposerFocus() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        let attachment = LocalFileAttachment(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        )
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        fixture.viewModel.replaceInputDraft("/model", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            providerID: "codex"
        )

        chatView.sendDraft()

        let request = try XCTUnwrap(chatView.reasoningMenuRequestState.pendingRequest)
        XCTAssertEqual(request.section, .models)
        XCTAssertEqual(chatView.composerActionRowConfiguration.reasoningMenuPresentationRequest, request)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [attachment])
        XCTAssertNil(appState.pendingComposerFocusToken)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testModelCommandAppliesShortNameCaseInsensitivelyWithoutSending() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        var requests: [ChatComposerActionRowView.ReasoningModelSelectionRequest] = []
        fixture.viewModel.replaceInputDraft("/model SOL", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            onModelChange: { request in
                requests.append(request)
                return .applied(selection: Self.appliedSelection)
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(requests.map(\.modelID), ["gpt-5.6-sol"])
        XCTAssertEqual(requests.map(\.providerID), ["codex"])
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testModelCommandClearsDraftWhenSelectionIsUnchanged() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/model gpt-5.5", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            onModelChange: { _ in .unchanged(Self.appliedSelection) },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNotNil(appState.pendingComposerFocusToken)
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testUnknownModelKeepsDraftAndAttachmentsAndSurfacesOptions() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        let attachment = LocalFileAttachment(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        )
        fixture.viewModel.state.stagedFileAttachments = [attachment]
        fixture.viewModel.replaceInputDraft("/model nonsense", source: .blockInputMarkdown)
        var requestCount = 0
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            onModelChange: { _ in
                requestCount += 1
                return .rejected
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/model nonsense")
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [attachment])
        XCTAssertNil(appState.pendingComposerFocusToken)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Model must be one of: sol|luna|gpt-5.5.")
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testRejectedModelChangeKeepsDraftAndReportsFallbackError() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/model luna", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            onModelChange: { _ in .rejected },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/model luna")
        XCTAssertNil(appState.pendingComposerFocusToken)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Model cannot be changed right now.")
    }

    func testRejectedModelChangePreservesUnderlyingError() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/model luna", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups,
            onModelChange: { _ in
                fixture.viewModel.lastTurnError = "Finish the current turn first."
                return .rejected
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "/model luna")
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Finish the current turn first.")
    }

    func testModelCommandSwitchesProviderWhenGroupsSpanProviders() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        var requests: [ChatComposerActionRowView.ReasoningModelSelectionRequest] = []
        fixture.viewModel.replaceInputDraft("/model opus", source: .blockInputMarkdown)
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: Self.codexModelGroups + Self.claudeModelGroups,
            onModelChange: { request in
                requests.append(request)
                return .applied(selection: Self.appliedSelection)
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(requests.map(\.providerID), ["claude"])
        XCTAssertEqual(requests.map(\.modelID), ["opus"])
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
    }

    func testModelCommandPassesThroughWhenOnlyOneModelIsAvailable() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appState = AppState()
        fixture.viewModel.replaceInputDraft("/model sol", source: .blockInputMarkdown)
        var requestCount = 0
        let chatView = makeChatView(
            fixture: fixture,
            appState: appState,
            modelGroups: [
                ChatComposerActionRowView.ReasoningModelGroup(
                    providerID: "codex",
                    providerTitle: "Codex",
                    options: [Self.modelOption(value: "gpt-5.6-sol", shortName: "sol", title: "GPT-5.6-Sol")]
                )
            ],
            onModelChange: { _ in
                requestCount += 1
                return .rejected
            },
            providerID: "codex"
        )

        chatView.sendDraft()

        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(chatView.reasoningMenuRequestState.pendingRequest)
        try await waitUntil("expected unsupported model command text to pass through") {
            await fixture.agentsManager.sentMessages() == ["/model sol"]
        }
    }

    private static var codexModelGroups: [ChatComposerActionRowView.ReasoningModelGroup] {
        [
            ChatComposerActionRowView.ReasoningModelGroup(
                providerID: "codex",
                providerTitle: "Codex",
                options: [
                    modelOption(value: "gpt-5.6-sol", shortName: "sol", title: "GPT-5.6-Sol"),
                    modelOption(value: "gpt-5.6-luna", shortName: "luna", title: "GPT-5.6-Luna"),
                    modelOption(value: "gpt-5.5", shortName: "gpt-5.5", title: "GPT-5.5")
                ]
            )
        ]
    }

    private static var claudeModelGroups: [ChatComposerActionRowView.ReasoningModelGroup] {
        [
            ChatComposerActionRowView.ReasoningModelGroup(
                providerID: "claude",
                providerTitle: "Claude",
                options: [
                    modelOption(providerID: "claude", value: "opus", shortName: "opus", title: "Opus")
                ]
            )
        ]
    }

    private static var appliedSelection: ChatComposerActionRowView.ReasoningSelection {
        ChatComposerActionRowView.ReasoningSelection(
            providerID: "codex",
            providerTitle: "Codex",
            modelID: "gpt-5.6-sol",
            modelTitle: "GPT-5.6-Sol",
            effortValue: "medium",
            effortTitle: "Medium",
            effortOptions: [],
            defaultEffortValue: nil,
            speedMode: .standard,
            supportsSpeedMode: false
        )
    }

    private static func modelOption(
        providerID: String = "codex",
        value: String,
        shortName: String,
        title: String
    ) -> ChatComposerActionRowView.ReasoningModelOption {
        ChatComposerActionRowView.ReasoningModelOption(
            providerID: providerID,
            value: value,
            title: title,
            shortName: shortName
        )
    }
}
