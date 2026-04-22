import SwiftUI

struct TaskListBlock: View {
    let tasks: [TaskEntry]

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

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
                HStack(alignment: .center, spacing: 10) {
                    TaskStatusIndicator(status: task.status)

                    Text(task.status == .inProgress ? (task.activeForm ?? task.content) : task.content)
                        .fontWeight(task.status == .inProgress ? .semibold : .regular)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .strikethrough(task.status == .completed)

                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .padding(chatBlockPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
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
}

private struct TaskStatusIndicator: View {
    let status: TaskEntry.Status

    var body: some View {
        Group {
            switch status {
            case .inProgress:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 16, height: 16)
            case .pending:
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
            case .completed:
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption.weight(.semibold))
        .frame(width: 16, height: 16, alignment: .center)
        .transaction(value: branchKey) { $0.animation = nil }
        .accessibilityLabel(status.accessibilityLabel)
    }

    private var branchKey: Int {
        switch status {
        case .inProgress:
            return 0
        case .pending:
            return 1
        case .completed:
            return 2
        }
    }
}

private extension TaskEntry.Status {
    var accessibilityLabel: String {
        switch self {
        case .inProgress:
            return "In progress"
        case .pending:
            return "Pending"
        case .completed:
            return "Completed"
        }
    }
}
