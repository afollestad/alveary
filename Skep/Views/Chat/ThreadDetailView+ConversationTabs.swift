import SwiftUI

struct ThreadDetailConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ActivitySignal
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if conversations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(conversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(statusColor(for: statusForConversation(conversation)))
                                        .frame(width: 8, height: 8)
                                        .opacity(showsStatusDot(for: statusForConversation(conversation)) ? 1 : 0)

                                    Text(label(for: conversation))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedConversation.persistentModelID == conversation.persistentModelID
                                                ? Color.accentColor.opacity(0.16)
                                                : Color.secondary.opacity(0.08)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(for: selectedConversation))
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

private extension ThreadDetailConversationTabs {
    func label(for conversation: Conversation) -> String {
        if let title = conversation.title, !title.isEmpty {
            return title
        }

        if conversation.isMain {
            return "Main"
        }

        return conversation.provider?.capitalized ?? "Conversation"
    }

    func showsStatusDot(for status: ActivitySignal) -> Bool {
        switch status {
        case .neutral, .stopped:
            return false
        case .busy, .idle, .error:
            return true
        }
    }

    func statusColor(for status: ActivitySignal) -> Color {
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
