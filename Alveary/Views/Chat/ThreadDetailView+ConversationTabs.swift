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
                        ForEach(Array(conversations.enumerated()), id: \.element.persistentModelID) { index, conversation in
                            ConversationTabChip(
                                conversation: conversation,
                                status: statusForConversation(conversation),
                                isSelected: selectedConversation.persistentModelID == conversation.persistentModelID,
                                tabIndex: index,
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
        .background {
            // Invisible ⌘W target. Per-chip bindings on the visible X buttons
            // didn't reliably override the system "Close Window" shortcut when
            // the first chip was selected, so ⌘W lives on one stable button
            // attached as a `.background` (outside the HStack layout so it
            // cannot shift spacing). Tying `.id` to the selected conversation
            // forces SwiftUI to remount the button when the selection changes
            // so the shortcut's bound action captures the current conversation
            // rather than the first one that ever mounted.
            Button("Close Conversation") {
                // Swallow ⌘W during an inline rename or when there's only
                // one conversation — but keep the button enabled so the key
                // event stays absorbed here and doesn't fall through to the
                // default "Close Window" and kill the app window.
                guard editingConversationID == nil else {
                    return
                }
                guard conversations.count > 1 else {
                    return
                }
                onRemove(selectedConversation)
            }
            .keyboardShortcut("w", modifiers: .command)
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .opacity(0)
            .allowsHitTesting(false)
            .id(selectedConversation.persistentModelID)
        }
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
    let tabIndex: Int
    @Binding var editingConversationID: PersistentIdentifier?
    let onSelect: () -> Void
    let onCommitRename: (String) -> Void
    let onClose: () -> Void

    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    private var isEditing: Bool {
        editingConversationID == conversation.persistentModelID
    }

    private var switchShortcut: KeyboardShortcut? {
        guard tabIndex < 9 else {
            return nil
        }
        return KeyboardShortcut(KeyEquivalent(Character("\(tabIndex + 1)")), modifiers: .command)
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
        .onAppear {
            // Cover the case where a chip is mounted while already in edit mode
            // (e.g. a view refresh). `.onChange(of: isEditing)` only fires on
            // transitions, so without this the TextField would stay empty.
            if isEditing {
                beginEditing()
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                beginEditing()
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
    var editingChip: some View {
        // Match the selectable chip's ZStack + trailing-padded capsule geometry so
        // toggling between display and rename doesn't resize the chip.
        ZStack(alignment: .trailing) {
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
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .padding(.trailing, 36)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )

            closeButton
                .padding(.trailing, 12)
        }
    }

    var selectableChip: some View {
        ZStack(alignment: .trailing) {
            selectButton

            closeButton
                .padding(.trailing, 12)
        }
    }

    var selectButton: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                AppMarkdownInlineLabel(text: conversation.displayName(), isSelected: isSelected)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .padding(.trailing, 36)
        }
        .buttonStyle(TabChipButtonStyle(isSelected: isSelected))
        .focusEffectDisabled()
        .accessibilityLabel(plainDisplayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Rename")) {
            editingConversationID = conversation.persistentModelID
        }
        .keyboardShortcut(switchShortcut)
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
        .accessibilityLabel("Remove \(plainDisplayName)")
    }

    var plainDisplayName: String {
        AppMarkdownInlineLabel.plainText(from: conversation.displayName())
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

    func beginEditing() {
        editText = conversation.customTitle ?? conversation.displayName()
        isFieldFocused = true
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
