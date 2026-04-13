import SwiftUI

struct SidebarThreadRow: View {
    let thread: AgentThread
    let status: ThreadStatus
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .offset(x: -3)
                .opacity(status == .stopped ? 0 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayName())
                    .foregroundStyle(thread.isEffectivelyUntitled ? .secondary : .primary)
                    .lineLimit(1)

                if let branch = thread.branch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityAction(named: Text("Rename")) {
            onRename()
        }
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .archived:
            return .secondary
        case .stopped:
            return .clear
        }
    }
}
