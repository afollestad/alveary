import XCTest

@testable import Alveary

final class AskUserQuestionOverlayStateTests: XCTestCase {
    func testCustomResponseMustHaveTextBeforeQuestionIsAnswered() {
        let question = PromptEntry.PromptQuestion(
            question: "What should happen?",
            header: nil,
            options: [PromptEntry.PromptOption(label: "Proceed", description: "Continue")],
            multiSelect: false
        )
        var state = AskUserQuestionOverlayState()
        state.selections[0] = [PromptEntry.PromptOption.customResponseID]

        XCTAssertFalse(state.isQuestionAnswered(question, at: 0))

        state.customResponses[0] = "  Use the safer path  "

        XCTAssertTrue(state.isQuestionAnswered(question, at: 0))
        let prompt = PromptEntry(id: "prompt", questions: [question], submittedSummary: nil)
        XCTAssertEqual(state.answers(for: prompt).first?.answer, "Use the safer path")
    }

    func testParsedCustomResponseRequiresTextWhenCustomOptionHasProviderId() {
        let question = PromptEntry.PromptQuestion(
            question: "What should happen?",
            header: nil,
            options: [
                PromptEntry.PromptOption(
                    id: "custom-provider-id",
                    label: "Tell the agent what to do differently",
                    description: "",
                    isCustomResponse: true
                )
            ],
            multiSelect: false
        )
        var state = AskUserQuestionOverlayState()
        state.selections[0] = ["custom-provider-id"]

        XCTAssertFalse(state.isQuestionAnswered(question, at: 0))

        state.customResponses[0] = "Try a smaller change"

        XCTAssertTrue(state.isQuestionAnswered(question, at: 0))
    }

    func testMultiSelectAnswersPreserveOptionOrderAndCustomText() {
        let question = PromptEntry.PromptQuestion(
            question: "Pick work",
            header: nil,
            options: [
                PromptEntry.PromptOption(label: "Fix tests", description: "Test repair"),
                PromptEntry.PromptOption(label: "Update docs", description: "Documentation")
            ],
            multiSelect: true
        )
        let prompt = PromptEntry(id: "prompt", questions: [question], submittedSummary: nil)
        var state = AskUserQuestionOverlayState()
        state.selections[0] = [
            PromptEntry.PromptOption.customResponseID,
            "Update docs",
            "Fix tests"
        ]
        state.customResponses[0] = "Add release notes"

        XCTAssertTrue(state.allQuestionsAnswered(in: prompt))
        let answers = state.answers(for: prompt)
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers.first?.question, "Pick work")
        XCTAssertEqual(answers.first?.answer, "Fix tests, Update docs, Add release notes")
    }

    func testReturnStyleSelectionDoesNotToggleSelectedMultiSelectOptionOff() {
        let option = PromptEntry.PromptOption(label: "Fix tests", description: "Test repair")
        let question = PromptEntry.PromptQuestion(
            question: "Pick work",
            header: nil,
            options: [option],
            multiSelect: true
        )
        var state = AskUserQuestionOverlayState()
        state.selections[0] = [option.id]

        state.select(option: option, for: question, at: 0, togglesMultiSelect: false)

        XCTAssertEqual(state.selections[0], Set([option.id]))

        state.select(option: option, for: question, at: 0, togglesMultiSelect: true)

        XCTAssertEqual(state.selections[0], Set<String>())
    }

    func testPrimaryActionTitleSwitchesToSubmitOnlyAfterEveryQuestionIsAnswered() {
        let prompt = PromptEntry(
            id: "prompt",
            questions: [
                PromptEntry.PromptQuestion(
                    question: "Scope?",
                    header: nil,
                    options: [PromptEntry.PromptOption(label: "Feature", description: "")],
                    multiSelect: false
                ),
                PromptEntry.PromptQuestion(
                    question: "Risk?",
                    header: nil,
                    options: [PromptEntry.PromptOption(label: "Low", description: "")],
                    multiSelect: false
                ),
                PromptEntry.PromptQuestion(
                    question: "Notes?",
                    header: nil,
                    options: [PromptEntry.PromptOption(label: "None", description: "")],
                    multiSelect: false
                )
            ],
            submittedSummary: nil
        )
        var state = AskUserQuestionOverlayState()

        XCTAssertEqual(state.primaryActionTitle(for: prompt), "Continue")

        state.selections[0] = ["Feature"]
        state.selections[1] = ["Low"]

        XCTAssertEqual(state.primaryActionTitle(for: prompt), "Continue")

        state.selections[2] = ["None"]

        XCTAssertEqual(state.primaryActionTitle(for: prompt), "Submit")
    }
}
