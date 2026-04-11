import Foundation
import SwiftUI

struct WorkingBlock: View {
    let tools: [ToolEntry]
    @State private var isExpanded = false

    private var editCount: Int {
        tools.filter { ["Edit", "Write", "MultiEdit"].contains($0.name) }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(tools) { tool in
                    ToolRow(tool: tool)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Working")
                        .font(.headline)

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var summary: String {
        if editCount > 0 {
            return "Used \(tools.count) tools, \(editCount) file edit\(editCount == 1 ? "" : "s")"
        }
        return "Used \(tools.count) tools"
    }
}

private struct ToolRow: View {
    let tool: ToolEntry
    @State private var isExpanded = false

    private var annotation: String? {
        guard let output = tool.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return nil
        }

        let lines = output.split(separator: "\n")
        guard lines.count <= 3, let last = lines.last else {
            return nil
        }

        let truncated = String(last)
        if truncated.count > 80 {
            return String(truncated.prefix(77)) + "..."
        }
        return truncated
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                DetailCodeBlock(title: "Input", content: prettyPrintedJSON(tool.input))

                if let output = tool.output {
                    if tool.isImage {
                        Label("Image output isn't previewed yet.", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !tool.noOutputExpected {
                            Text("No output")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        DetailCodeBlock(title: "Output", content: output)
                    }
                }

                if let stderr = tool.stderr,
                   !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailCodeBlock(title: "stderr", content: stderr, tint: .orange)
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(tool.isError ? .red : .green)

                    Text(tool.summary)
                        .font(.subheadline.weight(.semibold))

                    if tool.isInterrupted {
                        Text("Interrupted")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }

                    Spacer()
                }

                if let annotation {
                    Text("└ \(annotation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
        }
    }
}

private struct DetailCodeBlock: View {
    let title: String
    let content: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            ScrollView(.horizontal) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
        }
    }
}

struct SubAgentBlock: View {
    let agents: [SubAgentEntry]
    @State private var isExpanded = false

    private var runningCount: Int {
        agents.filter { !$0.isComplete }.count
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(agents) { agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(agent.isComplete ? Color.green : Color.blue)
                                .frame(width: 8, height: 8)

                            Text(agent.description)
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            Text(summary(for: agent))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let status = agent.statusDescription ?? agent.lastToolName {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !agent.tools.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(agent.tools) { tool in
                                    ToolRow(tool: tool)
                                }
                            }
                        }

                        if let result = agent.result,
                           !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DetailCodeBlock(title: "Result", content: result)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                    )
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(runningCount == 0 ? "Sub-agents finished" : "Running \(runningCount) of \(agents.count) sub-agents")
                    .font(.headline)

                Text("\(agents.count) agent\(agents.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func summary(for agent: SubAgentEntry) -> String {
        let tokens = tokenLabel(agent.totalTokens)
        return "\(agent.toolUseCount) tools · \(tokens)"
    }

    private func tokenLabel(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%.1fk tokens", Double(count) / 1_000)
        }
        return "\(count) tokens"
    }
}

struct TaskListBlock: View {
    let tasks: [TaskEntry]

    private var orderedTasks: [TaskEntry] {
        tasks.sorted { lhs, rhs in
            rank(lhs.status) < rank(rhs.status)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.headline)

            ForEach(orderedTasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(icon(for: task.status))

                    Text(task.status == .inProgress ? (task.activeForm ?? task.content) : task.content)
                        .fontWeight(task.status == .inProgress ? .semibold : .regular)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .strikethrough(task.status == .completed)

                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: 720, alignment: .leading)
    }

    private func rank(_ status: TaskEntry.Status) -> Int {
        switch status {
        case .inProgress:
            return 0
        case .pending:
            return 1
        case .completed:
            return 2
        }
    }

    private func icon(for status: TaskEntry.Status) -> String {
        switch status {
        case .inProgress:
            return "■"
        case .pending:
            return "□"
        case .completed:
            return "✓"
        }
    }
}

struct PromptBlock: View {
    let prompt: PromptEntry
    let isBusy: Bool
    let onSubmit: ([(question: String, answer: String)]) async -> String?

    @State private var selections: [Int: Set<String>] = [:]
    @State private var submittedSummary: String?
    @State private var isSubmitting = false

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
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Agent is asking")
                        .font(.headline)

                    ForEach(Array(prompt.questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 12) {
                            if let header = question.header, !header.isEmpty {
                                Text(header)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                            }

                            Text(question.question)
                                .font(.subheadline.weight(.semibold))

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(question.options, id: \.label) { option in
                                    Button {
                                        toggle(option.label, at: index, multiSelect: question.multiSelect)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: imageName(for: option.label, at: index, multiSelect: question.multiSelect))
                                                .foregroundStyle(
                                                    isSelected(option.label, at: index, multiSelect: question.multiSelect)
                                                        ? Color.accentColor
                                                        : Color.secondary
                                                )

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
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.06))
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
                        .buttonStyle(.borderedProminent)
                        .disabled(!isSubmitEnabled)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

private extension PromptBlock {
    func imageName(for label: String, at index: Int, multiSelect: Bool) -> String {
        let isActive = isSelected(label, at: index, multiSelect: multiSelect)
        if multiSelect {
            return isActive ? "checkmark.square.fill" : "square"
        }
        return isActive ? "largecircle.fill.circle" : "circle"
    }

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

struct ThinkingBlock: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .textSelection(.enabled)
        } label: {
            HStack(spacing: 10) {
                Text(isExpanded ? "💭" : "▸")
                Text(isExpanded ? "Thinking" : preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var preview: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? "Thinking"
        if firstLine.count > 80 {
            return String(firstLine.prefix(77)) + "..."
        }
        return firstLine
    }
}

private func prettyPrintedJSON(_ content: String) -> String {
    guard let data = content.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let pretty = String(data: prettyData, encoding: .utf8) else {
        return content
    }
    return pretty
}
