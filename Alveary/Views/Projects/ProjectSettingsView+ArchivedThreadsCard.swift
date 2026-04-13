import SwiftData
import SwiftUI

struct ProjectSettingsArchivedThreadsCard: View {
    let threads: [AgentThread]
    let onRestoreThread: (AgentThread) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Archived threads are hidden from the sidebar. Restore one to move it back into the project list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if threads.isEmpty {
                    Text("No archived threads")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(threads, id: \.persistentModelID) { thread in
                        ProjectSettingsArchivedThreadRow(
                            thread: thread,
                            onRestore: { onRestoreThread(thread) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        } label: {
            Label("Archived Threads", systemImage: "archivebox")
        }
    }
}

private struct ProjectSettingsArchivedThreadRow: View {
    let thread: AgentThread
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displayName())
                    .font(.headline)
                    .lineLimit(1)

                if let archivedAt = thread.archivedAt {
                    Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            Button("Restore", action: onRestore)
                .secondaryActionButtonStyle()
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
