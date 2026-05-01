import SwiftUI

struct TaskListBlock: View {
    let tasks: [TaskEntry]

    @Environment(\.transcriptBubbleMaxWidth) private var bubbleMaxWidth

    private var orderedTasks: [TaskEntry] {
        tasks.taskListPresentationOrder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .transcriptFont(.headline)

            ForEach(orderedTasks) { task in
                HStack(alignment: .center, spacing: 10) {
                    TaskStatusIndicator(status: task.status)

                    Text(task.status == .inProgress ? (task.activeForm ?? task.content) : task.content)
                        .fontWeight(task.status == .inProgress ? .semibold : .regular)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .strikethrough(task.status == .completed)

                    Spacer()
                }
                .transcriptFont(.subheadline)
            }
        }
        .padding(chatBlockPadding)
        .bubbleBackground(maxWidth: bubbleMaxWidth)
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
                    .scaleEffect(taskProgressSpinnerScale)
                    .frame(width: 16, height: 16)
            case .pending:
                Image(systemName: "square")
                    .foregroundStyle(.secondary)
            case .completed:
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(.green)
            }
        }
        .transcriptFont(.caption, weight: .semibold)
        .frame(width: 16, height: 16, alignment: .center)
        .transaction(value: branchKey) { $0.animation = nil }
        .accessibilityLabel(status.taskListAccessibilityLabel)
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

private let taskProgressSpinnerScale: CGFloat = 0.72
