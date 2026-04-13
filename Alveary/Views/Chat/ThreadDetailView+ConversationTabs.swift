import SwiftUI

struct ThreadDetailConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ActivitySignal
    let onSelect: (Conversation) -> Void
    let onRemove: (Conversation) -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if conversations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(conversations) { conversation in
                            ConversationTabChip(
                                label: conversation.displayName(),
                                status: statusForConversation(conversation),
                                isSelected: selectedConversation.persistentModelID == conversation.persistentModelID,
                                onSelect: { onSelect(conversation) },
                                onClose: { onRemove(conversation) }
                            )
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedConversation.displayName())
                        .font(.headline)

                    Text(selectedConversation.provider ?? "Conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onCreate()
            } label: {
                Label("New Conversation", systemImage: "plus")
            }
            .secondaryActionButtonStyle()
            .keyboardShortcut("t", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct ConversationTabChip: View {
    let label: String
    let status: ActivitySignal
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(showsStatusDot ? 1 : 0)

                    Text(label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private extension ConversationTabChip {
    var showsStatusDot: Bool {
        switch status {
        case .neutral, .stopped:
            return false
        case .busy, .idle, .error:
            return true
        }
    }

    var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .neutral, .stopped:
            return .clear
        }
    }
}
