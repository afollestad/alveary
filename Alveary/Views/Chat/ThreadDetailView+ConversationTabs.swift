import SwiftData
import SwiftUI

struct ThreadDetailConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ActivitySignal
    let onSelect: (Conversation) -> Void
    let onCommitRename: (Conversation, String) -> Void
    let onRemove: (Conversation) -> Void
    let onCreate: () -> Void

    @Binding var editingConversationID: PersistentIdentifier?

    var body: some View {
        HStack(spacing: 12) {
            if conversations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(conversations) { conversation in
                            ConversationTabChip(
                                conversation: conversation,
                                status: statusForConversation(conversation),
                                isSelected: selectedConversation.persistentModelID == conversation.persistentModelID,
                                editingConversationID: $editingConversationID,
                                onSelect: { onSelect(conversation) },
                                onCommitRename: { onCommitRename(conversation, $0) },
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
                .contentShape(Rectangle())
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
    let conversation: Conversation
    let status: ActivitySignal
    let isSelected: Bool
    @Binding var editingConversationID: PersistentIdentifier?
    let onSelect: () -> Void
    let onCommitRename: (String) -> Void
    let onClose: () -> Void

    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    private var isEditing: Bool {
        editingConversationID == conversation.persistentModelID
    }

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(showsStatusDot ? 1 : 0)

                    TextField("Conversation name", text: $editText)
                        .textFieldStyle(.plain)
                        .focused($isFieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Button(action: onSelect) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .opacity(showsStatusDot ? 1 : 0)

                        Text(conversation.displayName())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(conversation.displayName())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAction(named: Text("Rename")) {
                    editingConversationID = conversation.persistentModelID
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(conversation.displayName())")
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
        .contextMenu {
            Button("Rename...") {
                editingConversationID = conversation.persistentModelID
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: isEditing) { _, editing in
            if editing {
                editText = conversation.customTitle ?? conversation.displayName()
                isFieldFocused = true
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused && isEditing {
                commitRename()
            }
        }
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

    func commitRename() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onCommitRename(trimmed)
        }
        editingConversationID = nil
    }

    func cancelRename() {
        editingConversationID = nil
    }
}
