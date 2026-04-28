import Foundation
import SwiftUI

private let promptBlockPadding: CGFloat = 14
private let promptQuestionCardPadding: CGFloat = 12
private let promptBlockCornerRadius: CGFloat = 12
private let promptSubmittedPairSpacing: CGFloat = 8

struct PromptBlock: View {
    let prompt: PromptEntry
    let isBusy: Bool
    let onSubmit: ([(question: String, answer: String)]) async -> String?

    @State private var selections: [Int: Set<String>] = [:]
    @State private var customResponses: [Int: String] = [:]
    @State private var submittedSummary: String?
    @State private var isSubmitting = false
    @State private var measuredQuestionCardWidth: CGFloat = 0
    @FocusState private var focusedCustomResponseIndex: Int?

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    private var effectiveSummary: String? {
        prompt.submittedSummary ?? submittedSummary
    }

    private var submittedResponses: [SubmittedPromptResponse] {
        guard let effectiveSummary else {
            return []
        }
        return SubmittedPromptResponse.parse(from: effectiveSummary)
    }

    private var isSubmitEnabled: Bool {
        !isBusy && !isSubmitting && prompt.questions.enumerated().allSatisfy { index, question in
            isQuestionAnswered(question, at: index)
        }
    }

    private var unansweredQuestionCount: Int {
        prompt.questions.enumerated().filter { index, question in
            !isQuestionAnswered(question, at: index)
        }.count
    }

    private var submissionStatusText: String? {
        if isBusy {
            return "Wait for the current send or turn to finish before sending your selection."
        }
        guard unansweredQuestionCount > 0 else {
            return nil
        }
        let noun = unansweredQuestionCount == 1 ? "question" : "questions"
        return "Answer \(unansweredQuestionCount) more \(noun) before submitting."
    }

    private var maximumQuestionCardWidth: CGFloat? {
        guard bubbleMaxWidth.isFinite else {
            return nil
        }
        return max(0, bubbleMaxWidth - (promptBlockPadding * 2))
    }

    private var synchronizedQuestionCardWidth: CGFloat? {
        guard measuredQuestionCardWidth > 0 else {
            return nil
        }
        if let maximumQuestionCardWidth {
            return min(measuredQuestionCardWidth, maximumQuestionCardWidth)
        }
        return measuredQuestionCardWidth
    }

    private var promptContentWidth: CGFloat? {
        guard let synchronizedQuestionCardWidth else {
            return nil
        }

        return synchronizedQuestionCardWidth + (promptBlockPadding * 2)
    }

    init(
        prompt: PromptEntry,
        isBusy: Bool,
        initialSelections: [Int: Set<String>] = [:],
        initialCustomResponses: [Int: String] = [:],
        onSubmit: @escaping ([(question: String, answer: String)]) async -> String?
    ) {
        self.prompt = prompt
        self.isBusy = isBusy
        self.onSubmit = onSubmit
        _selections = State(initialValue: initialSelections)
        _customResponses = State(initialValue: initialCustomResponses)
    }

    var body: some View {
        Group {
            if let effectiveSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Submitted responses")
                        .transcriptFont(.headline)

                    if submittedResponses.isEmpty {
                        Text(effectiveSummary)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: promptSubmittedPairSpacing) {
                            ForEach(submittedResponses) { response in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(response.question)
                                        .transcriptFont(.subheadline, weight: .semibold)
                                        .foregroundStyle(.secondary)

                                    Text(response.answer)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                .padding(promptBlockPadding)
                .background(
                    RoundedRectangle(cornerRadius: promptBlockCornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            } else {
                VStack(alignment: .trailing, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Agent is asking")
                            .transcriptFont(.headline)

                        ForEach(Array(prompt.questions.enumerated()), id: \.offset) { index, question in
                            PromptQuestionCard(
                                question: question,
                                isSelected: { option in
                                    isSelected(option.id, at: index)
                                },
                                customResponse: Binding(
                                    get: { customResponses[index] ?? "" },
                                    set: { customResponses[index] = $0 }
                                ),
                                focusedCustomResponseIndex: $focusedCustomResponseIndex,
                                questionIndex: index,
                                onToggle: { option in
                                    toggle(option.id, at: index, multiSelect: question.multiSelect)
                                }
                            )
                            .background(QuestionCardWidthReader())
                            .frame(width: synchronizedQuestionCardWidth, alignment: .leading)
                        }
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        if let submissionStatusText {
                            Text(submissionStatusText)
                                .transcriptFont(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: synchronizedQuestionCardWidth, alignment: .leading)
                        }

                        Button("Submit") {
                            Task {
                                await submit()
                            }
                        }
                        .primaryActionButtonStyle()
                        .disabled(!isSubmitEnabled)
                    }
                }
                .padding(promptBlockPadding)
                .background(
                    RoundedRectangle(cornerRadius: promptBlockCornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .onPreferenceChange(PromptQuestionCardWidthPreferenceKey.self) { width in
                    measuredQuestionCardWidth = width
                }
            }
        }
        .frame(width: promptContentWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

private struct PromptQuestionCard: View {
    let question: PromptEntry.PromptQuestion
    let isSelected: (PromptEntry.PromptOption) -> Bool
    let customResponse: Binding<String>
    let focusedCustomResponseIndex: FocusState<Int?>.Binding
    let questionIndex: Int
    let onToggle: (PromptEntry.PromptOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let header = question.header, !header.isEmpty {
                Text(header)
                    .transcriptFont(.caption, weight: .semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppAccentFill.primary))
            }

            Text(question.question)
                .transcriptFont(.subheadline, weight: .semibold)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(question.renderedOptions, id: \.id) { option in
                    if option.isCustomResponse, isSelected(option) {
                        HStack(alignment: .center, spacing: 12) {
                            Button {
                                onToggle(option)
                            } label: {
                                optionGlyph(for: option)
                            }
                            .buttonStyle(.plain)

                            TextField("Enter your response", text: customResponse)
                                .textFieldStyle(.roundedBorder)
                                .focused(focusedCustomResponseIndex, equals: questionIndex)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Button {
                            onToggle(option)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                optionGlyph(for: option)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label)
                                        .transcriptFont(.subheadline, weight: .medium)
                                        .foregroundStyle(.primary)

                                    if !option.description.isEmpty {
                                        Text(option.description)
                                            .transcriptFont(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(promptQuestionCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: promptBlockCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func optionGlyph(for option: PromptEntry.PromptOption) -> some View {
        Image(systemName: imageName(for: option))
            .foregroundStyle(isSelected(option) ? Color.accentColor : Color.secondary)
            .frame(width: 20, height: 20, alignment: .center)
    }

    private func imageName(for option: PromptEntry.PromptOption) -> String {
        let isActive = isSelected(option)
        if question.multiSelect {
            return isActive ? "checkmark.square.fill" : "square"
        }
        return isActive ? "largecircle.fill.circle" : "circle"
    }
}

private extension PromptBlock {
    func isSelected(_ optionID: String, at index: Int) -> Bool {
        (selections[index] ?? []).contains(optionID)
    }

    func toggle(_ optionID: String, at index: Int, multiSelect: Bool) {
        var current = selections[index] ?? []
        if multiSelect {
            if current.contains(optionID) {
                current.remove(optionID)
            } else {
                current.insert(optionID)
            }
        } else {
            current = [optionID]
        }
        selections[index] = current

        if current.contains(PromptEntry.PromptOption.customResponseID) {
            focusedCustomResponseIndex = index
        } else if focusedCustomResponseIndex == index {
            focusedCustomResponseIndex = nil
        }
    }

    func isQuestionAnswered(_ question: PromptEntry.PromptQuestion, at index: Int) -> Bool {
        let selected = selections[index] ?? []
        guard question.multiSelect ? !selected.isEmpty : selected.count == 1 else {
            return false
        }

        if selected.contains(PromptEntry.PromptOption.customResponseID) {
            return trimmedCustomResponse(at: index) != nil
        }

        return true
    }

    func submit() async {
        guard isSubmitEnabled else {
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let answers = prompt.questions.enumerated().compactMap { index, question -> (question: String, answer: String)? in
            guard let selected = selections[index], !selected.isEmpty else {
                return nil
            }

            let orderedLabels = question.renderedOptions.compactMap { option -> String? in
                guard selected.contains(option.id) else {
                    return nil
                }

                if option.isCustomResponse {
                    return trimmedCustomResponse(at: index)
                }

                return option.label
            }
            return (question.question, orderedLabels.joined(separator: ", "))
        }

        submittedSummary = await onSubmit(answers)
    }

    func trimmedCustomResponse(at index: Int) -> String? {
        let trimmed = (customResponses[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct QuestionCardWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PromptQuestionCardWidthPreferenceKey.self, value: proxy.size.width)
        }
    }
}

private struct PromptQuestionCardWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SubmittedPromptResponse: Identifiable, Equatable {
    let question: String
    let answer: String

    var id: String { question + "\u{0}" + answer }

    static func parse(from summary: String) -> [SubmittedPromptResponse] {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else {
            return []
        }

        let paragraphs = trimmedSummary
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsedParagraphs = paragraphs.compactMap(parseParagraph)
        if parsedParagraphs.count == paragraphs.count {
            return parsedParagraphs
        }

        return trimmedSummary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(parseLegacyLine)
    }

    private static func parseParagraph(_ paragraph: String) -> SubmittedPromptResponse? {
        let lines = paragraph
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2,
              let questionLine = lines.first,
              let answerLine = lines.dropFirst().first,
              let question = payload(from: questionLine, prefix: "Q: "),
              let answer = payload(from: answerLine, prefix: "A: ") else {
            return nil
        }

        return SubmittedPromptResponse(question: question, answer: answer)
    }

    private static func parseLegacyLine(_ line: String) -> SubmittedPromptResponse? {
        guard let separator = line.range(of: ": ") else {
            return nil
        }

        let question = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else {
            return nil
        }

        return SubmittedPromptResponse(question: question, answer: answer)
    }

    private static func payload(from line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else {
            return nil
        }

        let payload = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return nil
        }
        return payload
    }
}

func prettyPrintedJSON(_ content: String) -> String {
    guard let data = content.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let pretty = String(data: prettyData, encoding: .utf8) else {
        return content
    }
    return pretty
}
