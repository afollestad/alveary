import Foundation
import SwiftUI

private let promptBlockPadding: CGFloat = 14
private let promptQuestionCardPadding: CGFloat = 12
private let promptBlockCornerRadius: CGFloat = 12

struct PromptBlock: View {
    let prompt: PromptEntry
    let isBusy: Bool
    let onSubmit: ([(question: String, answer: String)]) async -> String?

    @State private var selections: [Int: Set<String>] = [:]
    @State private var submittedSummary: String?
    @State private var isSubmitting = false

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    private var effectiveSummary: String? {
        prompt.submittedSummary ?? submittedSummary
    }

    private var isSubmitEnabled: Bool {
        !isBusy && !isSubmitting && prompt.questions.enumerated().allSatisfy { index, question in
            let selected = selections[index] ?? []
            return question.multiSelect ? !selected.isEmpty : selected.count == 1
        }
    }

    var body: some View {
        Group {
            if let effectiveSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You chose")
                        .font(.headline)

                    Text(effectiveSummary)
                        .foregroundStyle(.secondary)
                }
                .padding(promptBlockPadding)
                .background(
                    RoundedRectangle(cornerRadius: promptBlockCornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Agent is asking")
                        .font(.headline)

                    ForEach(Array(prompt.questions.enumerated()), id: \.offset) { index, question in
                        PromptQuestionCard(
                            question: question,
                            isSelected: { label in
                                isSelected(label, at: index, multiSelect: question.multiSelect)
                            },
                            onToggle: { label in
                                toggle(label, at: index, multiSelect: question.multiSelect)
                            }
                        )
                    }

                    HStack {
                        if isBusy {
                            Text("Wait for the current send or turn to finish before sending your selection.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

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
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

private struct PromptQuestionCard: View {
    let question: PromptEntry.PromptQuestion
    let isSelected: (String) -> Bool
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let header = question.header, !header.isEmpty {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppAccentFill.primary))
            }

            Text(question.question)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(question.options, id: \.label) { option in
                    Button {
                        onToggle(option.label)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: imageName(for: option.label))
                                .foregroundStyle(isSelected(option.label) ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)

                                if !option.description.isEmpty {
                                    Text(option.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(promptQuestionCardPadding)
        .background(
            RoundedRectangle(cornerRadius: promptBlockCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func imageName(for label: String) -> String {
        let isActive = isSelected(label)
        if question.multiSelect {
            return isActive ? "checkmark.square.fill" : "square"
        }
        return isActive ? "largecircle.fill.circle" : "circle"
    }
}

private extension PromptBlock {
    func isSelected(_ label: String, at index: Int, multiSelect: Bool) -> Bool {
        (selections[index] ?? []).contains(label)
    }

    func toggle(_ label: String, at index: Int, multiSelect: Bool) {
        var current = selections[index] ?? []
        if multiSelect {
            if current.contains(label) {
                current.remove(label)
            } else {
                current.insert(label)
            }
        } else {
            current = [label]
        }
        selections[index] = current
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

            let orderedLabels = question.options.compactMap { option in
                selected.contains(option.label) ? option.label : nil
            }
            return (question.question, orderedLabels.joined(separator: ", "))
        }

        submittedSummary = await onSubmit(answers)
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
