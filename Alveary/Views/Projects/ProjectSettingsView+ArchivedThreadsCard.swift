import SwiftData
import SwiftUI

/// Observation-backed wrapper around the archived-threads card.
///
/// `ProjectSettingsView` mounts this only after its first yield so selecting a
/// project paints before the archived-thread query runs.
struct ProjectSettingsArchivedThreadsSection: View {
    let onRequestRestoreThread: (AgentThread) -> Void
    let onRequestDeleteThread: (AgentThread) -> Void

    @Query private var archivedThreads: [AgentThread]

    init(
        projectPath: String,
        onRequestRestoreThread: @escaping (AgentThread) -> Void,
        onRequestDeleteThread: @escaping (AgentThread) -> Void
    ) {
        self.onRequestRestoreThread = onRequestRestoreThread
        self.onRequestDeleteThread = onRequestDeleteThread
        _archivedThreads = Query(
            filter: #Predicate<AgentThread> { thread in
                thread.archivedAt != nil && thread.project?.path == projectPath
            }
        )
    }

    var body: some View {
        ProjectSettingsArchivedThreadsCard(
            threads: projectSettingsArchivedThreads(archivedThreads),
            onRequestRestoreThread: onRequestRestoreThread,
            onRequestDeleteThread: onRequestDeleteThread
        )
    }
}

struct ProjectSettingsArchivedThreadsCard: View {
    let threads: [AgentThread]
    let onRequestRestoreThread: (AgentThread) -> Void
    let onRequestDeleteThread: (AgentThread) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Archived threads are hidden from the sidebar. Restore one to move it back into the project list, or delete it permanently.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if threads.isEmpty {
                    Text("No archived threads")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(threads, id: \.persistentModelID) { thread in
                        ProjectSettingsArchivedThreadRow(
                            thread: thread,
                            onRestore: { onRequestRestoreThread(thread) },
                            onDelete: { onRequestDeleteThread(thread) }
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
    let onDelete: () -> Void

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

            HStack(spacing: 6) {
                Button("Restore", action: onRestore)
                    .secondaryActionButtonStyle()
                    .controlSize(.small)

                Button("Delete", action: onDelete)
                    .destructiveActionButtonStyle()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
