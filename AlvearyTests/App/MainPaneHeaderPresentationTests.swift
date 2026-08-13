import Observation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class MainPaneHeaderPresentationTests: XCTestCase {
    func testPlainDestinationTitles() throws {
        let context = try makeContext()

        XCTAssertEqual(MainPaneHeaderPresentation(selection: nil, modelContext: context).title, .plain("Alveary"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .skills, modelContext: context).title, .plain("Skills"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .mcp, modelContext: context).title, .plain("MCP"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .scheduled, modelContext: context).title, .plain("Scheduled"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .settings, modelContext: context).title, .plain("Settings"))
    }

    /// Also covers the resolve gate keeping observation intact: the title is read off the resolved
    /// instance, which is the same object the rename mutates.
    func testProjectTitleTracksProjectName() throws {
        let context = try makeContext()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        context.insert(project)
        try context.save()
        let didInvalidate = LockedState(false)

        let initialPresentation = withObservationTracking {
            MainPaneHeaderPresentation(selection: .project(project), modelContext: context)
        } onChange: {
            didInvalidate.withLock { $0 = true }
        }

        XCTAssertEqual(initialPresentation.title, .plain("Alveary"))

        project.name = "Renamed Project"

        XCTAssertTrue(didInvalidate.withLock { $0 })
        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .project(project), modelContext: context).title,
            .plain("Renamed Project")
        )
    }

    func testThreadTitleUsesMarkdownDisplayNameAndTracksRename() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Fix `ContentView`")
        context.insert(thread)
        try context.save()
        let didInvalidate = LockedState(false)

        let initialPresentation = withObservationTracking {
            MainPaneHeaderPresentation(selection: .thread(thread), modelContext: context)
        } onChange: {
            didInvalidate.withLock { $0 = true }
        }

        XCTAssertEqual(initialPresentation.title, .markdown("Fix `ContentView`"))
        XCTAssertEqual(initialPresentation.title.accessibilityLabel, "Fix ContentView")

        thread.name = "Renamed thread"

        XCTAssertTrue(didInvalidate.withLock { $0 })
        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .thread(thread), modelContext: context).title,
            .markdown("Renamed thread")
        )
    }

    func testWhitespaceOnlyThreadNameUsesNewThreadFallback() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "   \n")
        context.insert(thread)
        try context.save()

        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .thread(thread), modelContext: context).title,
            .markdown(AgentThread.untitledName)
        )
    }

    func testNewConversationButtonOnlyAppearsForInitializedThreads() throws {
        let context = try makeContext()
        let thread = AgentThread(name: "Thread")
        let project = Project(path: "/tmp/project", name: "Project")
        context.insert(thread)
        context.insert(project)
        try context.save()

        XCTAssertFalse(
            MainPaneHeaderPresentation(selection: .thread(thread), modelContext: context).showsNewConversationButton
        )

        thread.hasCompletedInitialSetup = true

        XCTAssertTrue(
            MainPaneHeaderPresentation(selection: .thread(thread), modelContext: context).showsNewConversationButton
        )
        XCTAssertFalse(
            MainPaneHeaderPresentation(selection: .project(project), modelContext: context).showsNewConversationButton
        )
    }

    func testSettingsTitleIsStableAcrossTargetPages() throws {
        let context = try makeContext()
        let appState = AppState()

        for page in AppSettings.SettingsPage.allCases {
            appState.openSettings(targetPage: page)

            XCTAssertEqual(
                MainPaneHeaderPresentation(selection: appState.selectedSidebarItem, modelContext: context).title,
                .plain("Settings")
            )
        }
    }

    func testToolbarPaddingMatchesTranscriptInsets() {
        XCTAssertEqual(
            MainPaneToolbarLayout.systemLeadingContentInset + MainPaneToolbarLayout.leadingPadding,
            transcriptScrollLeadingInset
        )
        XCTAssertEqual(
            MainPaneToolbarLayout.systemTrailingContentInset + MainPaneToolbarLayout.trailingPadding,
            transcriptScrollTrailingInset
        )
    }

    /// The header resolves its selection token before reading it, so these models need a real store
    /// or every title would render the deleted-row fallback.
    private func makeContext() throws -> ModelContext {
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
        return ModelContext(container)
    }
}
