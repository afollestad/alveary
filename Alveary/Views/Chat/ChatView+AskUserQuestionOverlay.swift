import Foundation

struct AskUserQuestionOverlayState: Equatable {
    var currentQuestionIndex = 0
    var selections: [Int: Set<String>] = [:]
    var customResponses: [Int: String] = [:]
    var isSubmitting = false
    var isDismissing = false

    func isQuestionAnswered(_ question: PromptEntry.PromptQuestion, at index: Int) -> Bool {
        let selectedIDs = selections[index] ?? []
        let selectedOptions = question.renderedOptions.filter { selectedIDs.contains($0.id) }
        guard !selectedOptions.isEmpty else {
            return false
        }
        if selectedOptions.contains(where: \.isCustomResponse),
           customResponses[index]?.trimmedAskPromptText.isEmpty != false {
            return false
        }
        return true
    }

    func allQuestionsAnswered(in prompt: PromptEntry) -> Bool {
        prompt.questions.indices.allSatisfy { index in
            isQuestionAnswered(prompt.questions[index], at: index)
        }
    }

    mutating func select(
        option: PromptEntry.PromptOption,
        for question: PromptEntry.PromptQuestion,
        at questionIndex: Int,
        togglesMultiSelect: Bool
    ) {
        if question.multiSelect {
            var selectedIDs = selections[questionIndex] ?? []
            if togglesMultiSelect && selectedIDs.contains(option.id) {
                selectedIDs.remove(option.id)
            } else {
                selectedIDs.insert(option.id)
            }
            selections[questionIndex] = selectedIDs
        } else {
            selections[questionIndex] = [option.id]
        }
    }

    func primaryActionTitle(for prompt: PromptEntry) -> String {
        allQuestionsAnswered(in: prompt) ? "Submit" : "Continue"
    }

    func firstUnansweredQuestionIndex(in prompt: PromptEntry) -> Int? {
        prompt.questions.indices.first { index in
            !isQuestionAnswered(prompt.questions[index], at: index)
        }
    }

    func answers(for prompt: PromptEntry) -> [(question: String, answer: String)] {
        prompt.questions.indices.compactMap { questionIndex in
            let question = prompt.questions[questionIndex]
            let selectedIDs = selections[questionIndex] ?? []
            let answers = question.renderedOptions.compactMap { option -> String? in
                guard selectedIDs.contains(option.id) else {
                    return nil
                }
                if option.isCustomResponse {
                    let customAnswer = customResponses[questionIndex]?.trimmedAskPromptText ?? ""
                    return customAnswer.isEmpty ? nil : customAnswer
                }
                return option.label
            }
            guard !answers.isEmpty else {
                return nil
            }
            return (question: question.question, answer: answers.joined(separator: ", "))
        }
    }
}

extension ChatView {
    var composerInteractionOverlayID: String? {
        activeAskUserQuestionPrompt.map { "ask-user-question-\($0.id)" }
    }

    var composerInteractionOverlayConfiguration: AppKitComposerOverlayConfiguration? {
        askUserQuestionOverlayConfiguration
    }

    var activeAskUserQuestionPrompt: PromptEntry? {
        viewModel.state.grouper.latestUnansweredPrompt
    }

    var askUserQuestionOverlayConfiguration: AppKitComposerOverlayConfiguration? {
        guard let prompt = activeAskUserQuestionPrompt else {
            return nil
        }

        let state = askUserQuestionOverlayState(for: prompt)
        let questionIndex = clampedQuestionIndex(state.currentQuestionIndex, questionCount: prompt.questions.count)
        let question = prompt.questions[safe: questionIndex]
        let canInteract = !state.isSubmitting && !state.isDismissing
        let isCurrentQuestionAnswered = question.map {
            state.isQuestionAnswered($0, at: questionIndex)
        } ?? false
        let rows = question.map {
            askUserQuestionRows(
                prompt: prompt,
                question: $0,
                questionIndex: questionIndex,
                state: state,
                canInteract: canInteract
            )
        } ?? []

        return AppKitComposerOverlayConfiguration(
            id: "ask-user-question-\(prompt.id)-\(questionIndex)",
            panelConfiguration: AppKitComposerOverlayPanelView.Configuration(
                title: question?.question ?? "Answer question",
                rows: rows,
                pageText: prompt.questions.count > 1 ? "\(questionIndex + 1) of \(prompt.questions.count)" : nil,
                canNavigateBackward: questionIndex > 0,
                canNavigateForward: questionIndex < prompt.questions.count - 1,
                primaryTitle: state.primaryActionTitle(for: prompt),
                isPrimaryEnabled: canInteract &&
                    isCurrentQuestionAnswered &&
                    viewModel.canSubmitPromptAnswer(promptId: prompt.id),
                isResolving: state.isSubmitting || state.isDismissing,
                onNavigateBackward: {
                    navigateAskUserQuestion(promptID: prompt.id, delta: -1, questionCount: prompt.questions.count)
                },
                onNavigateForward: {
                    navigateAskUserQuestion(promptID: prompt.id, delta: 1, questionCount: prompt.questions.count)
                },
                onDismiss: {
                    dismissAskUserQuestionPrompt(prompt)
                },
                onPrimary: {
                    advanceOrSubmitAskUserQuestionPrompt(prompt, submitWhenComplete: true)
                }
            )
        )
    }

    func askUserQuestionRows(
        prompt: PromptEntry,
        question: PromptEntry.PromptQuestion,
        questionIndex: Int,
        state: AskUserQuestionOverlayState,
        canInteract: Bool
    ) -> [AppKitComposerOverlayOptionRowView.Configuration] {
        let selectedIDs = state.selections[questionIndex] ?? []
        let isQuestionAnswered = state.isQuestionAnswered(question, at: questionIndex)
        return question.renderedOptions.enumerated().map { optionIndex, option in
            let isSelected = selectedIDs.contains(option.id)
            let helpText = option.description.trimmedAskPromptText
            return AppKitComposerOverlayOptionRowView.Configuration(
                id: "\(prompt.id)-\(questionIndex)-\(option.id)",
                indexText: "\(optionIndex + 1).",
                title: option.isCustomResponse ? "" : option.label,
                helpText: option.isCustomResponse || helpText.isEmpty ? nil : helpText,
                isSelected: isSelected,
                showsSelectedChip: isSelected && isQuestionAnswered,
                isEnabled: canInteract,
                customPlaceholder: option.isCustomResponse ? customPlaceholder(for: option) : nil,
                customText: state.customResponses[questionIndex] ?? "",
                fontSize: AppKitComposerOverlayMetrics.compactOptionFontSize,
                fontWeight: AppKitComposerOverlayMetrics.compactOptionFontWeight,
                minimumHeight: AppKitComposerOverlayMetrics.compactOptionMinimumHeight,
                verticalPadding: AppKitComposerOverlayMetrics.compactOptionVerticalPadding,
                customFieldHeight: AppKitComposerOverlayMetrics.compactCustomFieldHeight,
                onSelect: {
                    selectAskUserQuestionOption(
                        prompt: prompt,
                        questionIndex: questionIndex,
                        option: option
                    )
                },
                onSubmitSelection: option.isCustomResponse ? nil : {
                    submitAskUserQuestionOptionSelection(
                        prompt: prompt,
                        questionIndex: questionIndex,
                        option: option
                    )
                },
                onCustomTextChanged: { text in
                    updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
                        state.customResponses[questionIndex] = text
                        if !text.trimmedAskPromptText.isEmpty {
                            if question.multiSelect {
                                var selectedIDs = state.selections[questionIndex] ?? []
                                selectedIDs.insert(option.id)
                                state.selections[questionIndex] = selectedIDs
                            } else {
                                state.selections[questionIndex] = [option.id]
                            }
                        }
                    }
                }
            )
        }
    }

    func askUserQuestionOverlayState(for prompt: PromptEntry) -> AskUserQuestionOverlayState {
        var state = askUserQuestionOverlayStates[prompt.id] ?? AskUserQuestionOverlayState()
        state.currentQuestionIndex = clampedQuestionIndex(state.currentQuestionIndex, questionCount: prompt.questions.count)
        return state
    }

    func updateAskUserQuestionOverlayState(
        promptID: String,
        questionCount: Int,
        _ update: (inout AskUserQuestionOverlayState) -> Void
    ) {
        var state = askUserQuestionOverlayStates[promptID] ?? AskUserQuestionOverlayState()
        update(&state)
        state.currentQuestionIndex = clampedQuestionIndex(state.currentQuestionIndex, questionCount: questionCount)
        askUserQuestionOverlayStates[promptID] = state
    }

    func navigateAskUserQuestion(promptID: String, delta: Int, questionCount: Int) {
        updateAskUserQuestionOverlayState(promptID: promptID, questionCount: questionCount) { state in
            state.currentQuestionIndex += delta
        }
    }

    func selectAskUserQuestionOption(
        prompt: PromptEntry,
        questionIndex: Int,
        option: PromptEntry.PromptOption
    ) {
        guard let question = prompt.questions[safe: questionIndex] else {
            return
        }

        updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
            state.select(option: option, for: question, at: questionIndex, togglesMultiSelect: true)
        }

        guard !question.multiSelect, !option.isCustomResponse else {
            return
        }
        advanceOrSubmitAskUserQuestionPrompt(prompt)
    }

    func submitAskUserQuestionOptionSelection(
        prompt: PromptEntry,
        questionIndex: Int,
        option: PromptEntry.PromptOption
    ) {
        guard let question = prompt.questions[safe: questionIndex] else {
            return
        }

        updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
            state.select(option: option, for: question, at: questionIndex, togglesMultiSelect: false)
        }

        advanceOrSubmitAskUserQuestionPrompt(prompt, submitWhenComplete: true)
    }

    func advanceOrSubmitAskUserQuestionPrompt(_ prompt: PromptEntry, submitWhenComplete: Bool = false) {
        let state = askUserQuestionOverlayState(for: prompt)
        let questionIndex = clampedQuestionIndex(state.currentQuestionIndex, questionCount: prompt.questions.count)
        guard let question = prompt.questions[safe: questionIndex],
              state.isQuestionAnswered(question, at: questionIndex) else {
            return
        }

        if submitWhenComplete, state.allQuestionsAnswered(in: prompt) {
            submitAskUserQuestionPrompt(prompt, state: state)
            return
        }

        if questionIndex < prompt.questions.count - 1 {
            updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
                state.currentQuestionIndex = questionIndex + 1
            }
            return
        }

        guard state.allQuestionsAnswered(in: prompt) else {
            if let firstUnanswered = state.firstUnansweredQuestionIndex(in: prompt) {
                updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
                    state.currentQuestionIndex = firstUnanswered
                }
            }
            return
        }

        submitAskUserQuestionPrompt(prompt, state: state)
    }

    func submitAskUserQuestionPrompt(_ prompt: PromptEntry, state: AskUserQuestionOverlayState) {
        let answers = state.answers(for: prompt)
        guard answers.count == prompt.questions.count else {
            return
        }

        updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
            state.isSubmitting = true
        }

        Task {
            do {
                _ = try await viewModel.answerPrompt(promptId: prompt.id, answers: answers)
                askUserQuestionOverlayStates[prompt.id] = nil
                requestScrollToBottom()
            } catch {
                updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
                    state.isSubmitting = false
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Failed to send answer: \(error.localizedDescription)"
                }
            }
        }
    }

    func dismissAskUserQuestionPrompt(_ prompt: PromptEntry) {
        updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
            state.isDismissing = true
        }

        Task {
            do {
                try await viewModel.dismissPrompt(promptId: prompt.id)
                askUserQuestionOverlayStates[prompt.id] = nil
            } catch {
                updateAskUserQuestionOverlayState(promptID: prompt.id, questionCount: prompt.questions.count) { state in
                    state.isDismissing = false
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Failed to dismiss prompt: \(error.localizedDescription)"
                }
            }
        }
    }

    func customPlaceholder(for option: PromptEntry.PromptOption) -> String {
        let description = option.description.trimmedAskPromptText
        guard option.label == PromptEntry.PromptOption.other.label else {
            return option.label
        }
        return description.isEmpty ? "Write your own response." : description
    }

    func clampedQuestionIndex(_ index: Int, questionCount: Int) -> Int {
        guard questionCount > 0 else {
            return 0
        }
        return min(max(index, 0), questionCount - 1)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var trimmedAskPromptText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
