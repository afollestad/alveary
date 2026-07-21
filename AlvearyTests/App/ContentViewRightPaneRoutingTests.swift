import XCTest

@testable import Alveary

final class ContentViewRightPaneRoutingTests: XCTestCase {
    func testMatchingContextualPaneTakesPrecedenceOverRequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .skills,
                skillsTarget: .newSkill,
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: true
            ),
            .skills(.newSkill)
        )
    }

    @MainActor
    func testRequestedDiffViewerReturnsAfterContextualPaneTemporarilyMasksIt() {
        let project = Project(path: "/tmp/diff-project", name: "Project")
        let appState = AppState()
        appState.showDiffViewer()
        let requestID = appState.diffViewerRequestID

        let scheduledDestination = RightPaneDestination.resolve(
            selection: .scheduled,
            skillsTarget: nil,
            mcpTarget: nil,
            scheduledTarget: .create,
            isDiffViewerRequested: appState.isDiffViewerRequested
        )
        let returnedProjectDestination = RightPaneDestination.resolve(
            selection: .project(project),
            skillsTarget: nil,
            mcpTarget: nil,
            scheduledTarget: .create,
            isDiffViewerRequested: appState.isDiffViewerRequested
        )

        XCTAssertEqual(scheduledDestination, .scheduled(.create))
        XCTAssertTrue(appState.isDiffViewerRequested)
        XCTAssertEqual(appState.diffViewerRequestID, requestID)
        XCTAssertEqual(returnedProjectDestination, .diff)
    }

    func testInactiveScreenTargetDoesNotMaskRequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .mcp,
                skillsTarget: .details("cached"),
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: true
            ),
            .diff
        )
    }

    func testRequestedDiffViewerRemainsInSharedWidthDomainAcrossProjectAndThreadSelections() {
        let project = Project(path: "/tmp/diff-project", name: "Project")
        let firstThread = AgentThread(name: "First thread", project: project)
        let secondThread = AgentThread(name: "Second thread", project: project)
        let selections: [SidebarItem] = [
            .project(project),
            .thread(firstThread),
            .thread(secondThread)
        ]

        let destinations = selections.map { selection in
            RightPaneDestination.resolve(
                selection: selection,
                skillsTarget: .newSkill,
                mcpTarget: .addCustom,
                scheduledTarget: .create,
                isDiffViewerRequested: true
            )
        }

        XCTAssertEqual(destinations, [.diff, .diff, .diff])
        XCTAssertEqual(destinations.compactMap(\.self).map(\.widthDomain), [.diff, .diff, .diff])
    }

    func testNoRequestAndNoMatchingContextualTargetProducesNoPane() {
        XCTAssertNil(
            RightPaneDestination.resolve(
                selection: .scheduled,
                skillsTarget: nil,
                mcpTarget: nil,
                scheduledTarget: nil,
                isDiffViewerRequested: false
            )
        )
    }

    func testEachDestinationUsesItsScreenWidthDomain() {
        XCTAssertEqual(RightPaneDestination.diff.widthDomain, .diff)
        XCTAssertEqual(RightPaneDestination.skills(.newSkill).widthDomain, .skills)
        XCTAssertEqual(RightPaneDestination.mcp(.addCustom).widthDomain, .mcp)
        XCTAssertEqual(RightPaneDestination.scheduled(.create).widthDomain, .scheduled)
    }

    func testDiffViewerCommandIntentUsesRenderedDestination() {
        XCTAssertEqual(DiffViewerCommandIntent.resolve(destination: .diff), .hideDiff)
        XCTAssertEqual(DiffViewerCommandIntent.resolve(destination: nil), .showDiff)
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .skills(.newSkill)),
            .deactivateContextAndShowDiff(.skills)
        )
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .mcp(.addCustom)),
            .deactivateContextAndShowDiff(.mcp)
        )
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .scheduled(.create)),
            .deactivateContextAndShowDiff(.scheduled)
        )
    }
}
