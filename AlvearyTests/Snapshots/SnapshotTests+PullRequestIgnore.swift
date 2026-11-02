import SwiftUI
import XCTest

@testable import Alveary

// Ignored pull requests: dimmed rows under "Show ignored", the empty state a fully ignored tab
// falls back to, the pane's ignored state, and each phase of the notifications-access sheet.
extension SnapshotTests {
    func testPullRequestsScreenShowsIgnoredRowsDimmed() async throws {
        let fixture = try await PullRequestsSnapshotFixture(
            ignored: [PullRequestIdentifier(owner: "octo", repo: "paraphrase", number: 566)],
            showsIgnored: true
        )

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_show_ignored"
        ) { fixture.screen }
    }

    func testPullRequestsScreenEmptyStateOffersShowIgnored() async throws {
        let authored = try XCTUnwrap(PullRequestsSnapshotFixture.defaultSummaries.first)
        let fixture = try await PullRequestsSnapshotFixture(summaries: [authored], ignored: [authored.id])

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1_120, height: 900),
            named: "pull_requests_all_ignored"
        ) { fixture.screen }
    }

    /// The tab row's ignore glyph tinted, and the Overview's banner naming why the list hides it.
    func testPullRequestPaneIgnored() async throws {
        let fixture = await PullRequestPaneSnapshots.makeLoadedFixture(ignored: true)

        await assertMacModelSnapshot(
            modelContainer: try PullRequestPaneSnapshots.makeModelContainer(),
            size: CGSize(width: 460, height: 400),
            named: "pull_request_pane_ignored"
        ) {
            fixture.pane
        }
    }

    func testPullRequestNotificationsAccessExplains() {
        assertNotificationsAccessSnapshot(.explain, named: "pull_request_notifications_access_explain")
    }

    func testPullRequestNotificationsAccessShowsCode() {
        assertNotificationsAccessSnapshot(
            .code(Self.notificationsAccessCode, didOpenBrowser: false),
            named: "pull_request_notifications_access_code"
        )
    }

    func testPullRequestNotificationsAccessWaitsAfterOpeningGitHub() {
        assertNotificationsAccessSnapshot(
            .code(Self.notificationsAccessCode, didOpenBrowser: true),
            named: "pull_request_notifications_access_waiting"
        )
    }

    func testPullRequestNotificationsAccessFailed() {
        assertNotificationsAccessSnapshot(
            .failed("GitHub didn't confirm the permission. Try again, or cancel to leave these pull requests as they were."),
            named: "pull_request_notifications_access_failed"
        )
    }

    private static let notificationsAccessCode = GitHubDeviceCode(
        code: "ABCD-1234",
        verificationURL: URL(string: "https://github.com/login/device") ?? URL(fileURLWithPath: "/")
    )

    private func assertNotificationsAccessSnapshot(
        _ phase: PullRequestNotificationsAccessRequest.Phase,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertMacSnapshot(
            PullRequestNotificationsAccessSheet(
                request: PullRequestNotificationsAccessRequest(
                    phase: phase,
                    pendingActions: [PullRequestIgnoreAction(
                        id: PullRequestIdentifier(owner: "octo", repo: "alveary", number: 41),
                        ignored: true
                    )]
                ),
                onContinue: {},
                onOpenBrowser: {},
                onCopyCode: {},
                onRetry: {},
                onCancel: {}
            ),
            size: CGSize(width: 420, height: 280),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}
