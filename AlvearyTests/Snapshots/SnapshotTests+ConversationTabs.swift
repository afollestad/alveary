import XCTest

@testable import Alveary

extension SnapshotTests {
    func testConversationTabsNeutralStatusDotVisible() {
        let thread = AgentThread(name: "Status Dot Coverage")
        let mainConversation = Conversation(
            id: "main",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let secondConversation = Conversation(
            id: "side",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, secondConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: mainConversation,
                statusForConversation: { conversation in
                    conversation.id == mainConversation.id ? .neutral : .busy
                },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_neutral_dot"
        )
    }

    func testConversationTabsInlineCodeChip() {
        let thread = AgentThread(name: "Inline Code Tab Coverage")
        let chipConversation = Conversation(
            id: "chip",
            title: "Test `code block`",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let plainConversation = Conversation(
            id: "plain",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [chipConversation, plainConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: chipConversation,
                statusForConversation: { _ in .idle },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_inline_code"
        )
    }

    func testConversationTabsSingleInlineCode() {
        let thread = AgentThread(name: "Single Conversation Inline Code")
        let onlyConversation = Conversation(
            id: "only",
            title: "Test `code block`",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        thread.conversations = [onlyConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: onlyConversation,
                statusForConversation: { _ in .idle },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_single_inline_code"
        )
    }

    func testConversationTabsDividerVisibleInDarkMode() {
        let thread = AgentThread(name: "Status Dot Coverage")
        let mainConversation = Conversation(
            id: "main",
            provider: "claude",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let secondConversation = Conversation(
            id: "side",
            title: "Follow-up",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, secondConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: mainConversation,
                statusForConversation: { conversation in
                    conversation.id == mainConversation.id ? .neutral : .busy
                },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_dark_divider",
            colorScheme: .dark
        )
    }
}
