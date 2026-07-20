import Observation
import XCTest

@testable import Alveary

@MainActor
final class MainPaneHeaderPresentationTests: XCTestCase {
    func testPlainDestinationTitles() {
        XCTAssertEqual(MainPaneHeaderPresentation(selection: nil).title, .plain("Alveary"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .skills).title, .plain("Skills"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .mcp).title, .plain("MCP"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .scheduled).title, .plain("Scheduled"))
        XCTAssertEqual(MainPaneHeaderPresentation(selection: .settings).title, .plain("Settings"))
    }

    func testProjectTitleTracksProjectName() {
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let didInvalidate = LockedState(false)

        let initialPresentation = withObservationTracking {
            MainPaneHeaderPresentation(selection: .project(project))
        } onChange: {
            didInvalidate.withLock { $0 = true }
        }

        XCTAssertEqual(initialPresentation.title, .plain("Alveary"))

        project.name = "Renamed Project"

        XCTAssertTrue(didInvalidate.withLock { $0 })
        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .project(project)).title,
            .plain("Renamed Project")
        )
    }

    func testThreadTitleUsesMarkdownDisplayNameAndTracksRename() {
        let thread = AgentThread(name: "Fix `ContentView`")
        let didInvalidate = LockedState(false)

        let initialPresentation = withObservationTracking {
            MainPaneHeaderPresentation(selection: .thread(thread))
        } onChange: {
            didInvalidate.withLock { $0 = true }
        }

        XCTAssertEqual(initialPresentation.title, .markdown("Fix `ContentView`"))
        XCTAssertEqual(initialPresentation.title.accessibilityLabel, "Fix ContentView")

        thread.name = "Renamed thread"

        XCTAssertTrue(didInvalidate.withLock { $0 })
        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .thread(thread)).title,
            .markdown("Renamed thread")
        )
    }

    func testWhitespaceOnlyThreadNameUsesNewThreadFallback() {
        let thread = AgentThread(name: "   \n")

        XCTAssertEqual(
            MainPaneHeaderPresentation(selection: .thread(thread)).title,
            .markdown(AgentThread.untitledName)
        )
    }

    func testNewConversationButtonOnlyAppearsForInitializedThreads() {
        let thread = AgentThread(name: "Thread")

        XCTAssertFalse(
            MainPaneHeaderPresentation(selection: .thread(thread)).showsNewConversationButton
        )

        thread.hasCompletedInitialSetup = true

        XCTAssertTrue(
            MainPaneHeaderPresentation(selection: .thread(thread)).showsNewConversationButton
        )
        XCTAssertFalse(
            MainPaneHeaderPresentation(selection: .project(Project(path: "/tmp/project", name: "Project")))
                .showsNewConversationButton
        )
    }

    func testSettingsTitleIsStableAcrossTargetPages() {
        let appState = AppState()

        for page in AppSettings.SettingsPage.allCases {
            appState.openSettings(targetPage: page)

            XCTAssertEqual(
                MainPaneHeaderPresentation(selection: appState.selectedSidebarItem).title,
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
}
