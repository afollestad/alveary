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
            // Hide "Rename..." when *any* tab is being edited. Swapping
            // `editingConversationID` directly from one chip to another left the
            // target chip stuck in editing state without an input field — the
            // simultaneous unmount of the in-flight chip's TextField and mount
            // of the target chip's within a single SwiftUI update pass didn't
            // converge. Force users to finish the in-flight rename first —
            // mirrors the same guard on sidebar thread rows. Empty ViewBuilder
            // result suppresses the menu entirely on macOS.
            if editingConversationID == nil {
                Button("Rename...") {
                    editingConversationID = conversation.persistentModelID
                }
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
        // Inner layout + outer shell come from `SelectableTabChip`'s shared
        // `.tabChipContentLayout()` / `.tabChipShell(...)` modifiers so toggling
        // between display and rename cannot resize the chip. Editing mode uses:
        //   • `NSColor.textBackgroundColor` as the capsule fill (system text-input
        //     surface) so the chip clearly reads as an input field — the previous
        //     `secondary.opacity(0.08)` matched an unselected tab and gave no
        //     visual signal that the user was typing into a field.
        //   • a 1pt accent-colored stroke as a focus indicator, matching macOS
        //     Finder's inline-rename treatment.
        //   • `showsCloseButton: false` on the shell so the `×` hides during
        //     rename — the close button's role (commit? cancel? delete?) is
        //     ambiguous while editing. The shell still reserves the trailing
        //     36pt so the chip width does not jump as the user enters/leaves
        //     edit mode.
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
        .tabChipContentLayout()
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 1)
        )
        .tabChipShell(
            closeAccessibilityLabel: "Remove \(plainDisplayName)",
            onClose: onClose,
            showsCloseButton: false
        )
    }

    var selectableChip: some View {
        // Gate the rename accessibility action on `editingConversationID == nil`,
        // matching the context-menu button's gate above. Passing `nil` when another
        // tab is editing suppresses the rotor entry entirely (see the `if let`
        // inside `SelectableTabChip`'s `.accessibilityActions` builder).
        let renameAction: (() -> Void)? = editingConversationID == nil
            ? { editingConversationID = conversation.persistentModelID }
            : nil
        return SelectableTabChip(
            displayName: conversation.displayName(),
            statusColor: statusColor,
            isSelected: isSelected,
            selectAccessibilityLabel: plainDisplayName,
            closeAccessibilityLabel: "Remove \(plainDisplayName)",
            selectShortcut: switchShortcut,
            renameAccessibilityAction: renameAction,
            onSelect: onSelect,
            onClose: onClose
        )
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
