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
                tabs: conversationTabs(
                    thread.conversations,
                    status: { _ in .stopped },
                    canRemove: { !$0.isMain }
                ),
                selectedConversationModelID: mainConversation.persistentModelID,
                onSelect: { _ in },
                onCommitRename: { _, _ in },
                onRemove: { _ in },
                editingConversationID: .constant(nil)
            ),
            size: CGSize(width: 640, height: 72),
            named: "conversation_tabs_scheduled_main_retained"
        )
    }

}
