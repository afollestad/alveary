import AppKit
import SwiftData
import SwiftUI

/// Width of the trailing sentinel view at the end of the scrollable tab content and of
/// the breathing gap between the `New Conversation` button and the trailing-edge divider.
/// Shared across the sentinel frame, the button's leading padding, and the divider
/// gating math so all three stay synchronized.
private let tabsTrailingSentinelWidth: CGFloat = 12

struct ThreadDetailConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ThreadStatus
    let onSelect: (Conversation) -> Void
    let onCommitRename: (Conversation, String) -> Void
    let onRemove: (Conversation) -> Void
    let onCreate: () -> Void

    @Binding var editingConversationID: PersistentIdentifier?
    @Environment(\.colorScheme) private var colorScheme
    @State private var tabsScrollGeometry = ConversationTabsScrollGeometry()

    var body: some View {
        HStack(spacing: 0) {
            if conversations.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        // Outer wrapper HStack hosts the 12pt trailing sentinel as
                        // its own view. The sentinel does double duty: it reserves
                        // the 12pt breathing gap between the last chip and the
                        // overlay divider at scroll-to-end, AND gives a scroll
                        // target whose trailing edge is the content's absolute
                        // trailing edge. Without it, `proxy.scrollTo(lastChip)`
                        // stops when the chip's trailing hits the viewport — a
                        // separate 12pt `.padding(.trailing, 12)` on the chip
                        // HStack would then sit offscreen, leaving the last chip
                        // visually butted against the divider.
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
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
                                    .id(conversation.persistentModelID)
                                }
                            }
                            // Leading pane-edge inset lives *inside* the scrollable
                            // content so chips can scroll past the pane's visible
                            // leading edge while the first chip still appears 20pt
                            // in at `contentOffset == 0`.
                            .padding(.leading, 20)

                            Color.clear
                                .frame(width: tabsTrailingSentinelWidth, height: 1)
                                .id(ScrollTarget.trailingSentinel)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onScrollGeometryChange(for: ConversationTabsScrollGeometry.self) { geometry in
                        ConversationTabsScrollGeometry(
                            contentWidth: geometry.contentSize.width,
                            containerWidth: geometry.containerSize.width,
                            contentOffset: geometry.contentOffset.x
                        )
                    } action: { _, newValue in
                        tabsScrollGeometry = newValue
                    }
                    .overlay(alignment: .trailing) {
                        if hasTabsBehindTrailingEdge {
                            Rectangle()
                                .fill(tabsDividerColor)
                                .frame(width: 1, height: 18)
                                .accessibilityHidden(true)
                        }
                    }
                    // Scroll on selection change. For non-last chips a default
                    // `nil`-anchor minimum-scroll-to-visible keeps already-visible
                    // chips from jumping; for the last chip we target the trailing
                    // sentinel so the 12pt trailing gap stays on-screen and the
                    // chip keeps its breathing room before the divider.
                    .onChange(of: selectedConversation.persistentModelID, initial: true) { _, newID in
                        if conversations.last?.persistentModelID == newID {
                            proxy.scrollTo(ScrollTarget.trailingSentinel, anchor: .trailing)
                        } else {
                            proxy.scrollTo(newID)
                        }
                    }
                    // `createConversation` appends the new conversation, so any
                    // count-grow should scroll all the way to the end. Targeting the
                    // trailing sentinel (rather than `conversations.last?.id`) keeps
                    // the sentinel's 12pt width on-screen — mirrors the terminal
                    // pane's `sessions.count` hook in intent but adds the sentinel
                    // because the conversation-tabs row has a trailing gap the
                    // terminal row doesn't.
                    .onChange(of: conversations.count) { oldCount, newCount in
                        guard newCount > oldCount else {
                            return
                        }
                        proxy.scrollTo(ScrollTarget.trailingSentinel, anchor: .trailing)
                    }
                }
            } else {
                AppMarkdownInlineLabel(
                    text: selectedConversation.displayName(),
                    textStyle: .headline
                )
                .padding(.leading, 20)
                Spacer()
            }

            Button {
                onCreate()
            } label: {
                Label("New Conversation", systemImage: "plus")
            }
            .secondaryActionButtonStyle()
            .help("New Conversation (\(KeyboardShortcut.newConversation.displayString))")
            .padding(.leading, tabsTrailingSentinelWidth)
        }
        .padding(.trailing, 20)
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
            .keyboardShortcut(.closeConversation)
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
            closeHelpText: "Close Conversation (\(KeyboardShortcut.closeConversation.displayString))",
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
            return .blue
        case .unread:
            return .green
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

private extension ThreadDetailConversationTabs {
    /// Maximum distance the tab row can scroll given current content / container width.
    var tabsMaxScrollableDistance: CGFloat {
        max(0, tabsScrollGeometry.contentWidth - tabsScrollGeometry.containerWidth)
    }

    /// `true` when a tab chip is clipped by the trailing edge of the scroll area. Gates
    /// the trailing divider so it only appears when a chip is actually hidden, and
    /// hides once the last chip is flush with the viewport trailing. Mirrors the
    /// terminal pane's gating, with an extra adjustment: the trailing sentinel adds
    /// `tabsTrailingSentinelWidth` to `contentWidth` as reserved trailing space — the
    /// last `tabsTrailingSentinelWidth` of scroll is the sentinel itself, not a chip.
    /// Subtracting it from `maxScroll` means the divider hides as soon as the last
    /// chip's trailing reaches the viewport, rather than hanging on while the sentinel
    /// scrolls in, and avoids a false-positive divider when chips nearly fit the
    /// viewport and only the sentinel overflows.
    var hasTabsBehindTrailingEdge: Bool {
        let effectiveMaxScroll = tabsMaxScrollableDistance - tabsTrailingSentinelWidth
        return effectiveMaxScroll > 0.5
            && tabsScrollGeometry.contentOffset < effectiveMaxScroll - 0.5
    }

    /// Matches the terminal pane's divider tint so the two surfaces stay visually aligned.
    var tabsDividerColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.3)
    }
}

/// Snapshot of the conversation-tab row's scroll state. Populated by
/// `onScrollGeometryChange(for:of:action:)` so the trailing-edge divider can gate on
/// whether there is off-screen content further right.
private struct ConversationTabsScrollGeometry: Equatable {
    var contentWidth: CGFloat = 0
    var containerWidth: CGFloat = 0
    var contentOffset: CGFloat = 0
}

/// `ScrollViewProxy` targets. Chips use their `persistentModelID`; the trailing
/// sentinel is a 12pt-wide view at the very end of the scrollable content that
/// provides both the visible gap before the overlay divider at scroll-to-end and a
/// scroll target whose trailing edge equals the content's absolute trailing edge.
private enum ScrollTarget: Hashable {
    case trailingSentinel
}
