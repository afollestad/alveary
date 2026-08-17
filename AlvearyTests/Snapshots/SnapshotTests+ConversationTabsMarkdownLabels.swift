import AppKit
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testConversationTabsMarkdownLinkTitle() {
        let thread = AgentThread(name: "Markdown Link Tab Coverage")
        let linkConversation = Conversation(
            id: "link",
            title: "[.alveary.json](.alveary.json)",
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
        thread.conversations = [linkConversation, plainConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                tabs: conversationTabs(thread.conversations, status: { _ in .unread }),
                selectedConversationModelID: linkConversation.persistentModelID,
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_markdown_link"
        )
    }

}
