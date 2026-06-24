@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitComposerOverlayInteractionTests {
    func testAnsweringFourthQuestionReturnsToSkippedFirstQuestion() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let prompt = fourQuestionPromptForRevisit()
        let chatView = makeClickSubmitChatView(
            fixture: fixture,
            initialAskUserQuestionOverlayStates: [
                prompt.id: AskUserQuestionOverlayState(
                    currentQuestionIndex: 3,
                    selections: [1: ["Two"], 2: ["Three"]]
                )
            ]
        )
        configureAnsweredPrompt(prompt, fixture: fixture)

        let routedState = try XCTUnwrap(chatView.submitAskUserQuestionOptionSelection(
            prompt: prompt,
            questionIndex: 3,
            option: prompt.questions[3].options[0]
        ))
        let calls = await fixture.agentsManager.approvalCalls()

        XCTAssertEqual(routedState.currentQuestionIndex, 0)
        XCTAssertTrue(calls.isEmpty)
    }

    func testAnsweringFirstSkippedQuestionMovesToThirdSkippedQuestion() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let prompt = fourQuestionPromptForRevisit()
        let chatView = makeClickSubmitChatView(
            fixture: fixture,
            initialAskUserQuestionOverlayStates: [
                prompt.id: AskUserQuestionOverlayState(
                    currentQuestionIndex: 0,
                    selections: [1: ["Two"], 3: ["Four"]]
                )
            ]
        )
        configureAnsweredPrompt(prompt, fixture: fixture)

        let routedState = try XCTUnwrap(chatView.submitAskUserQuestionOptionSelection(
            prompt: prompt,
            questionIndex: 0,
            option: prompt.questions[0].options[0]
        ))
        let calls = await fixture.agentsManager.approvalCalls()

        XCTAssertEqual(routedState.currentQuestionIndex, 2)
        XCTAssertTrue(calls.isEmpty)
    }

    func testAnsweringFinalSkippedQuestionLeavesPromptReadyToSubmit() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let prompt = fourQuestionPromptForRevisit()
        let chatView = makeClickSubmitChatView(
            fixture: fixture,
            initialAskUserQuestionOverlayStates: [
                prompt.id: AskUserQuestionOverlayState(
                    currentQuestionIndex: 2,
                    selections: [0: ["One"], 1: ["Two"], 3: ["Four"]]
                )
            ]
        )
        configureAnsweredPrompt(prompt, fixture: fixture)

        let routedState = try XCTUnwrap(chatView.submitAskUserQuestionOptionSelection(
            prompt: prompt,
            questionIndex: 2,
            option: prompt.questions[2].options[0]
        ))
        let calls = await fixture.agentsManager.approvalCalls()

        XCTAssertEqual(routedState.currentQuestionIndex, 2)
        XCTAssertEqual(routedState.primaryActionTitle(for: prompt), "Submit")
        XCTAssertTrue(calls.isEmpty)
    }

    func testPrimaryActionSendsAnswersWhenAllQuestionsAreAnswered() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let prompt = fourQuestionPromptForRevisit()
        let chatView = makeClickSubmitChatView(
            fixture: fixture,
            initialAskUserQuestionOverlayStates: [
                prompt.id: AskUserQuestionOverlayState(
                    currentQuestionIndex: 2,
                    selections: [0: ["One"], 1: ["Two"], 2: ["Three"], 3: ["Four"]]
                )
            ]
        )
        configureAnsweredPrompt(prompt, fixture: fixture)

        let routedState = chatView.advanceOrSubmitAskUserQuestionPrompt(prompt)
        try await waitUntil("expected complete prompt approval call") {
            await fixture.agentsManager.approvalCalls().isEmpty == false
        }
        let calls = await fixture.agentsManager.approvalCalls()

        XCTAssertNil(routedState)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.decision, .allow)
        XCTAssertTrue(call.updatedInput?.contains(#""One?":"One""#) ?? false)
        XCTAssertTrue(call.updatedInput?.contains(#""Two?":"Two""#) ?? false)
        XCTAssertTrue(call.updatedInput?.contains(#""Three?":"Three""#) ?? false)
        XCTAssertTrue(call.updatedInput?.contains(#""Four?":"Four""#) ?? false)
    }

    func testPanelReturnUsesPrimarySubmitWhenAskUserQuestionIsComplete() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        var selectionCount = 0
        var primaryCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "one",
                        indexText: "1.",
                        title: "One",
                        isFocused: true,
                        onSelect: { selectionCount += 1 },
                        onSubmitSelection: { selectionCount += 1 }
                    )
                ],
                primaryTitle: "Submit",
                prefersPrimaryActionForReturn: true,
                onDismiss: {},
                onPrimary: { primaryCount += 1 }
            )
        )

        XCTAssertTrue(panel.handleKeyDown(makeKeyEvent(characters: "\r", keyCode: 36)))

        XCTAssertEqual(selectionCount, 0)
        XCTAssertEqual(primaryCount, 1)
    }

    func testFocusedRowReturnUsesPrimarySubmitWhenAskUserQuestionIsComplete() throws {
        let panel = AppKitComposerOverlayPanelView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        var selectionCount = 0
        var primaryCount = 0
        panel.configure(
            AppKitComposerOverlayPanelView.Configuration(
                title: "Question",
                rows: [
                    AppKitComposerOverlayOptionRowView.Configuration(
                        id: "one",
                        indexText: "1.",
                        title: "One",
                        isFocused: true,
                        onSelect: { selectionCount += 1 },
                        onSubmitSelection: { selectionCount += 1 }
                    )
                ],
                primaryTitle: "Submit",
                prefersPrimaryActionForReturn: true,
                onDismiss: {},
                onPrimary: { primaryCount += 1 }
            )
        )

        let row = try XCTUnwrap(panel.rowViews.first)
        row.keyDown(with: makeKeyEvent(characters: "\r", keyCode: 36))

        XCTAssertEqual(selectionCount, 0)
        XCTAssertEqual(primaryCount, 1)
    }
}

private func fourQuestionPromptForRevisit() -> PromptEntry {
    PromptEntry(
        id: "prompt-revisit-four",
        questions: [
            PromptEntry.PromptQuestion(
                question: "One?",
                header: nil,
                options: [PromptEntry.PromptOption(label: "One", description: "")],
                multiSelect: false
            ),
            PromptEntry.PromptQuestion(
                question: "Two?",
                header: nil,
                options: [PromptEntry.PromptOption(label: "Two", description: "")],
                multiSelect: false
            ),
            PromptEntry.PromptQuestion(
                question: "Three?",
                header: nil,
                options: [PromptEntry.PromptOption(label: "Three", description: "")],
                multiSelect: false
            ),
            PromptEntry.PromptQuestion(
                question: "Four?",
                header: nil,
                options: [PromptEntry.PromptOption(label: "Four", description: "")],
                multiSelect: false
            )
        ],
        submittedSummary: nil
    )
}
