import XCTest

@testable import Alveary

/// A thread's linked pull requests share the right-pane lane with the Pull
/// Requests screen's, so routing has to answer for both selections.
extension ContentViewRightPaneRoutingTests {
    func testThreadSelectionRendersAPullRequestPane() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .thread(AgentThread(name: "Thread")),
                targets: RightPaneContextualTargets(pullRequest: Self.pullRequestTarget),
                isDiffViewerRequested: false
            ),
            .pullRequest(Self.pullRequestTarget)
        )
    }

    /// Same precedence as every other contextual pane: never two right panes.
    func testThreadPullRequestPaneMasksARequestedDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .thread(AgentThread(name: "Thread")),
                targets: RightPaneContextualTargets(pullRequest: Self.pullRequestTarget),
                isDiffViewerRequested: true
            ),
            .pullRequest(Self.pullRequestTarget)
        )
    }

    func testThreadSelectionWithoutATargetStillRoutesToTheDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .thread(AgentThread(name: "Thread")),
                targets: RightPaneContextualTargets(),
                isDiffViewerRequested: true
            ),
            .diff
        )
    }

    /// Projects own pull-request links too, so their selections route the same
    /// way threads do — including masking a requested Diff Viewer.
    func testProjectSelectionRendersAPullRequestPane() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .project(Project(path: "/tmp/alpha", name: "Alpha")),
                targets: RightPaneContextualTargets(pullRequest: Self.pullRequestTarget),
                isDiffViewerRequested: true
            ),
            .pullRequest(Self.pullRequestTarget)
        )
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .project(Project(path: "/tmp/alpha", name: "Alpha")),
                targets: RightPaneContextualTargets(pullRequest: Self.pullRequestTarget),
                isDiffViewerRequested: false
            ),
            .pullRequest(Self.pullRequestTarget)
        )
    }

    func testProjectSelectionWithoutATargetStillRoutesToTheDiffViewer() {
        XCTAssertEqual(
            RightPaneDestination.resolve(
                selection: .project(Project(path: "/tmp/alpha", name: "Alpha")),
                targets: RightPaneContextualTargets(),
                isDiffViewerRequested: true
            ),
            .diff
        )
    }

    func testPullRequestPaneReportsThePullRequestFeature() {
        XCTAssertEqual(RightPaneDestination.pullRequest(Self.pullRequestTarget).feature, .pullRequests)
    }
}
