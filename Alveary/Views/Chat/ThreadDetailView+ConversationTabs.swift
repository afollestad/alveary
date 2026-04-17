import AppKit
import SwiftData
import SwiftUI

struct ThreadDetailConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ThreadStatus
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
                AppMarkdownInlineLabel(
                    text: selectedConversation.displayName(),
                    textStyle: .headline
                )
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

private struct ConversationTabChip: View {
    let conversation: Conversation
    let status: ThreadStatus
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
        Group {
            if isEditing {
                editingChip
            } else {
                selectableChip
            }
        }
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

private struct ConversationTabSelectButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .contentShape(Capsule(style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return AppSelectionStyle.pressedFill
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return Color.secondary.opacity(0.08)
    }
}

private extension ConversationTabChip {
    var editingChip: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                TextField("Conversation name", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    var selectableChip: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    AppMarkdownInlineLabel(text: conversation.displayName())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .padding(.trailing, 36)
            }
            .buttonStyle(ConversationTabSelectButtonStyle(isSelected: isSelected))
            .focusEffectDisabled()
            .accessibilityLabel(conversation.displayName())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: Text("Rename")) {
                editingConversationID = conversation.persistentModelID
            }

            closeButton
                .padding(.trailing, 12)
        }
    }

    var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel("Remove \(conversation.displayName())")
    }

    var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .unread:
            return .blue
        case .error:
            return .red
        case .stopped, .archived:
            return .secondary
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
