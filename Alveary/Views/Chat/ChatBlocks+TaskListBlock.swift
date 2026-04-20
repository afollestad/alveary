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
