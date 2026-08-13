import SwiftData
import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testMainPaneHeaderPlainTitle() throws {
        let context = try makeMainPaneHeaderContext()

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(
                    selection: .skills,
                    modelContext: context
                ),
                onNewConversation: nil
            )
            .padding(8),
            size: CGSize(width: 180, height: 56),
            named: "main_pane_header_plain"
        )
    }

    func testMainPaneHeaderRichThreadTitleWithCreateButton() throws {
        let thread = AgentThread(name: "Fix `ContentView`", hasCompletedInitialSetup: true)
        let context = try makeMainPaneHeaderContext(inserting: thread)

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(
                    selection: .thread(thread),
                    modelContext: context
                ),
                onNewConversation: {}
            )
            .padding(8),
            size: CGSize(width: 260, height: 56),
            named: "main_pane_header_rich_thread"
        )
    }

    func testMainPaneHeaderLongThreadTitleKeepsCreateButtonVisible() throws {
        let thread = AgentThread(
            name: "Investigate `ContentView` and @/Users/alice/Development/Alveary/Alveary/App/ContentView.swift before release",
            hasCompletedInitialSetup: true
        )
        let context = try makeMainPaneHeaderContext(inserting: thread)

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(
                    selection: .thread(thread),
                    modelContext: context
                ),
                onNewConversation: {}
            )
            .padding(8),
            size: CGSize(width: 420, height: 56),
            named: "main_pane_header_long_thread"
        )
    }

    func testMainPaneHeaderDisabledCreateButton() throws {
        let thread = AgentThread(name: "Blocked thread", hasCompletedInitialSetup: true)
        let context = try makeMainPaneHeaderContext(inserting: thread)

        assertMacSnapshot(
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(
                    selection: .thread(thread),
                    modelContext: context
                ),
                onNewConversation: nil
            )
            .padding(8),
            size: CGSize(width: 240, height: 56),
            named: "main_pane_header_disabled_create"
        )
    }

    /// The header resolves its selection token before reading it, so a thread has to be in a real
    /// store for these baselines to render a title instead of the deleted-row fallback.
    private func makeMainPaneHeaderContext(inserting thread: AgentThread? = nil) throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        if let thread {
            context.insert(thread)
            try context.save()
        }
        return context
    }
}
