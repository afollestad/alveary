import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testConversationTabsScheduledMainHidesOnlyItsCloseAffordance() {
        let thread = AgentThread(name: "Scheduled Task", mode: .task)
        let mainConversation = Conversation(
            id: "scheduled-main",
            title: "Scheduled Task",
            provider: "codex",
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let sideConversation = Conversation(
            id: "scheduled-side",
            title: "Follow-up",
            provider: "codex",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations = [mainConversation, sideConversation]

        assertMacSnapshot(
            ThreadDetailConversationTabs(
                conversations: thread.conversations,
                selectedConversation: mainConversation,
                statusVersion: 0,
                statusForConversation: { _ in .stopped },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: false,
                canRemove: { !$0.isMain },
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_scheduled_main_retained"
        )
    }

    func testConversationTabsCreateDisabled() {
        let thread = AgentThread(name: "Disabled Create Coverage")
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
                statusVersion: 0,
                statusForConversation: { _ in .stopped },
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                onCreate: {},
                isCreateDisabled: true,
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_create_disabled"
        )
    }
}
