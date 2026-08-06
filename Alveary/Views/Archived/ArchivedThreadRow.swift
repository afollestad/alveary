import SwiftUI

struct ArchivedThreadRow: View {
    let item: ArchivedThreadItem
    let isBusy: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(
                    "Archived \(item.archivedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())"
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Every row repeats these two visible titles, so name the thread in the
            // accessibility label — otherwise VoiceOver reads a wall of "Unarchive, Delete".
            HStack(spacing: 6) {
                Button(action: onRestore) {
                    ActionButtonLabel(title: "Unarchive", icon: .system("tray.and.arrow.up"))
                }
                .secondaryActionButtonStyle()
                .accessibilityLabel("Unarchive \(item.title)")

                Button(action: onDelete) {
                    ActionButtonLabel(title: "Delete", icon: .system("trash"))
                }
                .destructiveActionButtonStyle()
                .accessibilityLabel("Delete \(item.title)")
            }
            .controlSize(.small)
            .disabled(isBusy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
    }
}

func archivedThreadRestoreConfirmationMessage(title: String) -> String {
    "Restoring \"\(title)\" puts it back in the sidebar. Local transcript and worktree metadata stay in Alveary. "
        + "The next run starts a fresh provider session, and Alveary attaches a restore summary to your next message."
}
