import Foundation
import SwiftUI

struct WorkingBlock: View {
    let tools: [ToolEntry]
    private let initiallyExpandedToolIDs: Set<String>
    @State private var isExpanded = false

    private var singleTool: ToolEntry? {
        tools.count == 1 ? tools.first : nil
    }

    init(
        tools: [ToolEntry],
        initiallyExpanded: Bool = false,
        initiallyExpandedToolIDs: Set<String> = []
    ) {
        self.tools = tools
        self.initiallyExpandedToolIDs = initiallyExpandedToolIDs
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var editCount: Int {
        tools.filter { ["Edit", "Write", "MultiEdit"].contains($0.name) }.count
    }

    private var failureCount: Int {
        tools.filter(\.isError).count
    }

    private var interruptedCount: Int {
        tools.filter(\.isInterrupted).count
    }

    private var isWorking: Bool {
        tools.contains { !$0.isComplete }
    }

    private var title: String {
        isWorking ? "Working" : "Done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    DisclosureChevron(isExpanded: isExpanded)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)

                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let singleTool {
                    ToolRow(
                        tool: singleTool,
                        initiallyExpanded: true,
                        showsDisclosure: false
                    )
                    .padding(.top, 12)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tools) { tool in
                            ToolRow(
                                tool: tool,
                                initiallyExpanded: initiallyExpandedToolIDs.contains(tool.id)
                            )
                        }
                    }
                    .padding(.top, 12)
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
        let toolLabel = "tool" + (tools.count == 1 ? "" : "s")
        if isWorking {
            if editCount > 0 {
                return "\(tools.count) \(toolLabel), \(editCount) update\(editCount == 1 ? "" : "s") so far"
            }
            return "\(tools.count) \(toolLabel)"
        }

        var parts = ["\(tools.count) \(toolLabel)"]
        if editCount > 0 {
            parts.append("\(editCount) update\(editCount == 1 ? "" : "s")")
        }
        if failureCount > 0 {
            parts.append("\(failureCount) failed")
        } else if interruptedCount > 0 {
            parts.append("\(interruptedCount) interrupted")
        }
        return parts.joined(separator: ", ")
    }
}

private struct ToolRow: View {
    let tool: ToolEntry
    let showsDisclosure: Bool
    @State private var isExpanded = false

    private let detailLeadingInset: CGFloat = 42
    private let annotationLeadingInset: CGFloat = 42

    init(tool: ToolEntry, initiallyExpanded: Bool = false, showsDisclosure: Bool = true) {
        self.tool = tool
        self.showsDisclosure = showsDisclosure
        _isExpanded = State(initialValue: showsDisclosure ? initiallyExpanded : true)
    }

    private var annotation: String? {
        guard let output = tool.output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            return nil
        }

        let lines = output.split(separator: "\n")
        guard lines.count <= 3, let last = lines.last else {
            return nil
        }

        return String(last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDisclosure {
                Button {
                    isExpanded.toggle()
                } label: {
                    toolHeader
                }
                .buttonStyle(.plain)
            } else {
                toolHeader
            }

            if let annotation {
                Text("└ \(annotation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.leading, annotationLeadingInset)
            }

            if isExpanded {
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
                .padding(.leading, detailLeadingInset)
            }
        }
    }

    @ViewBuilder
    private var toolHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 10) {
                if showsDisclosure {
                    DisclosureChevron(isExpanded: isExpanded)
                } else {
                    Color.clear
                        .frame(width: 12, height: 12)
                }

                Image(systemName: tool.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tool.isError ? .red : .green)
                    .frame(width: 18, alignment: .center)
            }
            .frame(width: annotationLeadingInset, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(tool.summary)
                        .font(.subheadline.weight(.semibold))

                    if tool.isInterrupted {
                        Text("Interrupted")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 2)
        }
        .contentShape(Rectangle())
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
                HStack(alignment: .top, spacing: 0) {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.bottom, 8)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
        }
    }
}

private struct DisclosureChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .frame(width: 12, alignment: .center)
            .foregroundStyle(.secondary)
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
