import XCTest

@testable import Alveary

final class ContentViewRightPaneRoutingTests: XCTestCase {
    private static let pullRequestTarget = PullRequestPaneTarget.details(
        PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    )

    func testMatchingContextualPaneTakesPrecedenceOverRequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .skills,
                targets: RightPaneContextualTargets(skills: .newSkill),
                isDiffViewerRequested: true
            ),
            .skills(.newSkill)
        )
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .pullRequests,
                targets: RightPaneContextualTargets(pullRequest: Self.pullRequestTarget),
                isDiffViewerRequested: true
            ),
            .pullRequest(Self.pullRequestTarget)
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
            targets: RightPaneContextualTargets(scheduled: .create),
            isDiffViewerRequested: appState.isDiffViewerRequested
        )
        let returnedProjectDestination = RightPaneDestination.resolve(
            selection: .project(project),
            targets: RightPaneContextualTargets(scheduled: .create),
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
                targets: RightPaneContextualTargets(skills: .details("cached")),
                isDiffViewerRequested: true
            ),
            .diff
        )
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .pullRequests,
                targets: RightPaneContextualTargets(skills: .details("cached")),
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
                targets: RightPaneContextualTargets(
                    skills: .newSkill,
                    mcp: .addCustom,
                    scheduled: .create,
                    pullRequest: Self.pullRequestTarget
                ),
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
                targets: RightPaneContextualTargets(),
                isDiffViewerRequested: false
            )
        )
        XCTAssertNil(
            RightPaneDestination.resolve(
                selection: .pullRequests,
                targets: RightPaneContextualTargets(),
                isDiffViewerRequested: false
            )
        )
    }

    func testEachDestinationUsesItsScreenWidthDomain() {
        XCTAssertEqual(RightPaneDestination.diff.widthDomain, .diff)
        XCTAssertEqual(RightPaneDestination.skills(.newSkill).widthDomain, .skills)
        XCTAssertEqual(RightPaneDestination.mcp(.addCustom).widthDomain, .mcp)
        XCTAssertEqual(RightPaneDestination.scheduled(.create).widthDomain, .scheduled)
        XCTAssertEqual(RightPaneDestination.pullRequest(Self.pullRequestTarget).widthDomain, .pullRequests)
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
        XCTAssertEqual(
            DiffViewerCommandIntent.resolve(destination: .pullRequest(Self.pullRequestTarget)),
            .deactivateContextAndShowDiff(.pullRequests)
        )
    }
}
