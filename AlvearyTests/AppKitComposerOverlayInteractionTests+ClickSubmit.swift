@preconcurrency import AppKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayInteractionTests {
    func testDefaultOptionRowClickSelectsOnly() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        var selectionCount = 0
        var submitSelectionCount = 0
        row.configure(clickTestRow(
            onSelect: { selectionCount += 1 },
            onSubmitSelection: { submitSelectionCount += 1 }
        ))

        row.performMouseActivationForTesting()

        XCTAssertEqual(selectionCount, 1)
        XCTAssertEqual(submitSelectionCount, 0)
    }

    func testSubmitSelectionOptionRowClickSubmitsOnly() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        var selectionCount = 0
        var submitSelectionCount = 0
        row.configure(clickTestRow(
            mouseActivationBehavior: .submitSelection,
            onSelect: { selectionCount += 1 },
            onSubmitSelection: { submitSelectionCount += 1 }
        ))

        row.performMouseActivationForTesting()

        XCTAssertEqual(selectionCount, 0)
        XCTAssertEqual(submitSelectionCount, 1)
    }

    func testSubmitSelectionCustomOptionRowClickFocusesInsteadOfSubmitting() {
        let row = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        var selectionCount = 0
        var submitSelectionCount = 0
        row.configure(clickTestRow(
            title: "",
            customPlaceholder: "Write your own response.",
            mouseActivationBehavior: .submitSelection,
            onSelect: { selectionCount += 1 },
            onSubmitSelection: { submitSelectionCount += 1 }
        ))

        row.performMouseActivationForTesting()

        XCTAssertEqual(selectionCount, 1)
        XCTAssertEqual(submitSelectionCount, 0)
    }

    func testExitPlanModeRowsConfigureMouseActivationBehavior() throws {
        let chatView = try makeClickSubmitChatView()
        let rows = chatView.exitPlanModeRows(
            approval: exitPlanModeApproval(),
            state: ExitPlanModeOverlayState(),
            canInteract: true
        )

        XCTAssertEqual(rows[0].mouseActivationBehavior, .submitSelection)
        XCTAssertEqual(rows[1].mouseActivationBehavior, .select)
    }

    func testAskUserQuestionRowsConfigureMouseActivationBehavior() throws {
        let chatView = try makeClickSubmitChatView()
        let questions = askUserQuestionActivationQuestions()
        let prompt = PromptEntry(id: "prompt-1", questions: questions, submittedSummary: nil)

        let singleChoiceRows = chatView.askUserQuestionRows(
            prompt: prompt,
            question: questions[0],
            questionIndex: 0,
            state: AskUserQuestionOverlayState(),
            canInteract: true
        )
        let multiSelectRows = chatView.askUserQuestionRows(
            prompt: prompt,
            question: questions[1],
            questionIndex: 1,
            state: AskUserQuestionOverlayState(),
            canInteract: true
        )

        XCTAssertEqual(singleChoiceRows[0].mouseActivationBehavior, .submitSelection)
        XCTAssertEqual(singleChoiceRows[1].mouseActivationBehavior, .select)
        XCTAssertEqual(multiSelectRows[0].mouseActivationBehavior, .select)
        XCTAssertEqual(multiSelectRows[1].mouseActivationBehavior, .select)
    }

    func testClickingAnsweredEarlierAskUserQuestionSingleChoiceRowSubmitsUpdatedAnswers() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let prompt = multiQuestionPromptForClickSubmit()
        let chatView = makeClickSubmitChatView(
            fixture: fixture,
            initialAskUserQuestionOverlayStates: [
                prompt.id: AskUserQuestionOverlayState(
                    currentQuestionIndex: 0,
                    selections: [0: ["Feature"], 1: ["Low"]]
                )
            ]
        )
        configureAnsweredPrompt(prompt, fixture: fixture)
        let bugFixRow = AppKitComposerOverlayOptionRowView(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        let rows = rowsForFirstQuestion(prompt, chatView: chatView)
        XCTAssertTrue(rows[0].isSelected)
        bugFixRow.configure(rows[1])

        bugFixRow.performMouseActivationForTesting()
        try await waitUntil("expected click submit approval call") {
            await fixture.agentsManager.approvalCalls().isEmpty == false
        }
        let calls = await fixture.agentsManager.approvalCalls()

        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.decision, .allow)
        XCTAssertTrue(call.updatedInput?.contains(#""Scope?":"Bug fix""#) ?? false)
        XCTAssertTrue(call.updatedInput?.contains(#""Risk?":"Low""#) ?? false)
    }
}

private func clickTestRow(
    title: String = "One",
    customPlaceholder: String? = nil,
    mouseActivationBehavior: AppKitComposerOverlayOptionRowView.MouseActivationBehavior = .select,
    onSelect: @escaping () -> Void,
    onSubmitSelection: @escaping () -> Void
) -> AppKitComposerOverlayOptionRowView.Configuration {
    AppKitComposerOverlayOptionRowView.Configuration(
        id: "one",
        indexText: "1.",
        title: title,
        customPlaceholder: customPlaceholder,
        mouseActivationBehavior: mouseActivationBehavior,
        onSelect: onSelect,
        onSubmitSelection: onSubmitSelection,
        onCustomTextChanged: { _ in }
    )
}

@MainActor
private func makeClickSubmitChatView() throws -> ChatView {
    try makeClickSubmitChatView(fixture: ConversationViewModelTestFixture())
}

@MainActor
private func makeClickSubmitChatView(
    fixture: ConversationViewModelTestFixture,
    initialAskUserQuestionOverlayStates: [String: AskUserQuestionOverlayState] = [:]
) -> ChatView {
    ChatView(
        viewModel: fixture.viewModel,
        conversation: fixture.conversation,
        composerCapabilities: ComposerCapabilities(
            supportedPermissionModes: [],
            supportsMidTurnSteering: true
        ),
        providerOptions: [.init(value: "claude", title: "Claude Code")],
        modelOptions: [
            .init(
                value: AppSettings.defaultModelValue,
                title: ChatComposerTextSupport.modelLabel(for: AppSettings.defaultModelValue)
            )
        ],
        selectedModelOptionID: AppSettings.defaultModelValue,
        effortOptions: [],
        onModelOptionChange: { _ in },
        defaultEnterBehavior: .queue,
        providerID: "claude",
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
        appState: AppState(),
        initialAskUserQuestionOverlayStates: initialAskUserQuestionOverlayStates
    )
}

private func exitPlanModeApproval() -> PendingToolApproval {
    PendingToolApproval(
        request: ToolApprovalRequest(
            sessionId: "session-click-submit",
            toolUseId: "exit-plan-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        ),
        status: .pending
    )
}

private func askUserQuestionActivationQuestions() -> [PromptEntry.PromptQuestion] {
    [
        PromptEntry.PromptQuestion(
            question: "Pick one",
            header: nil,
            options: [
                PromptEntry.PromptOption(label: "A", description: ""),
                PromptEntry.PromptOption(label: "Custom", description: "", isCustomResponse: true)
            ],
            multiSelect: false
        ),
        PromptEntry.PromptQuestion(
            question: "Pick many",
            header: nil,
            options: [
                PromptEntry.PromptOption(label: "A", description: "")
            ],
            multiSelect: true
        )
    ]
}

private func multiQuestionPromptForClickSubmit() -> PromptEntry {
    PromptEntry(
        id: "prompt-click-submit",
        questions: [
            PromptEntry.PromptQuestion(
                question: "Scope?",
                header: nil,
                options: [
                    PromptEntry.PromptOption(label: "Feature", description: ""),
                    PromptEntry.PromptOption(label: "Bug fix", description: "")
                ],
                multiSelect: false
            ),
            PromptEntry.PromptQuestion(
                question: "Risk?",
                header: nil,
                options: [
                    PromptEntry.PromptOption(label: "Low", description: "")
                ],
                multiSelect: false
            )
        ],
        submittedSummary: nil
    )
}

@MainActor
private func configureAnsweredPrompt(
    _ prompt: PromptEntry,
    fixture: ConversationViewModelTestFixture
) {
    fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
        request: ToolApprovalRequest(
            sessionId: "session-click-submit",
            toolUseId: prompt.id,
            toolName: "AskUserQuestion",
            toolInput: askUserQuestionToolInput(for: prompt)
        ),
        status: .pending
    )
    fixture.viewModel.state.grouper.items = [.promptBlock(id: prompt.id, prompt: prompt)]
}

@MainActor
private func rowsForFirstQuestion(
    _ prompt: PromptEntry,
    chatView: ChatView
) -> [AppKitComposerOverlayOptionRowView.Configuration] {
    chatView.askUserQuestionRows(
        prompt: prompt,
        question: prompt.questions[0],
        questionIndex: 0,
        state: chatView.askUserQuestionOverlayState(for: prompt),
        canInteract: true
    )
}

private func askUserQuestionToolInput(for prompt: PromptEntry) -> String {
    let questions = prompt.questions.map { question -> [String: Any] in
        [
            "question": question.question,
            "options": question.options.map { option in
                [
                    "label": option.label,
                    "description": option.description
                ]
            },
            "multiSelect": question.multiSelect
        ]
    }
    guard JSONSerialization.isValidJSONObject(["questions": questions]),
          let data = try? JSONSerialization.data(withJSONObject: ["questions": questions], options: [.sortedKeys]),
          let value = String(data: data, encoding: .utf8) else {
        return #"{"questions":[]}"#
    }
    return value
}
