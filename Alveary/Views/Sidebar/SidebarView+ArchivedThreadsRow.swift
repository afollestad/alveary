import SwiftUI

struct SidebarArchivedThreadsRow: View {
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)

                Label("Archived", systemImage: "archivebox")
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
