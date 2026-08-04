import AppKit
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    /// The octicon is asset-backed rather than an SF Symbol, so only a rendered baseline proves it
    /// draws at the row's icon size and takes the row's tint.
    func testAppKitPullRequestToolRowUsesTheSharedOcticon() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptToolHeaderRowView()
                view.configure(
                    .init(
                        summary: "List involved PRs",
                        leadingIcon: .pullRequest,
                        phase: .success
                    )
                )
                return view
            },
            size: CGSize(width: 420, height: 44),
            named: "pull_request_tool_row_octicon"
        )
    }

    func testPullRequestListWidgetRendersARowPerPullRequest() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptHostToolWidgetRowView()
                view.configure(.init(entry: self.pullRequestListEntry(), bubbleMaxWidth: 640))
                return view
            },
            size: CGSize(width: 700, height: 220),
            named: "pull_request_list_widget"
        )
    }

    func testPullRequestListWidgetRendersARowPerPullRequestDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptHostToolWidgetRowView()
                view.configure(.init(entry: self.pullRequestListEntry(), bubbleMaxWidth: 640))
                return view
            },
            size: CGSize(width: 700, height: 220),
            named: "pull_request_list_widget_dark",
            colorScheme: .dark
        )
    }

    /// A long list opens at `collapsedRowLimit` rows with the rest behind one action, so it
    /// cannot push the rest of the turn off screen.
    func testPullRequestListWidgetCollapsesALongList() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitTranscriptHostToolWidgetRowView()
                view.configure(.init(entry: self.longPullRequestListEntry(), bubbleMaxWidth: 640))
                return view
            },
            size: CGSize(width: 700, height: 480),
            named: "pull_request_list_widget_collapsed"
        )
    }

    private func longPullRequestListEntry() -> HostToolWidgetEntry {
        let rows = (1...12).map { number in
            PullRequestListWidgetContent.Row(
                identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: number),
                title: "Change number \(number)",
                status: .open
            )
        }
        return HostToolWidgetEntry(
            id: "tool-list-prs-long",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.listToolName),
            content: .pullRequestList(
                PullRequestListWidgetContent(
                    filter: .all,
                    rows: rows,
                    totalCount: rows.count,
                    hasWarnings: false,
                    message: nil,
                    status: .listed
                )
            ),
            isComplete: true
        )
    }

    /// Every status has its own octicon and tint, so one row of each guards the mapping.
    private func pullRequestListEntry() -> HostToolWidgetEntry {
        let rows: [PullRequestListWidgetContent.Row] = [
            .init(
                identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
                title: "Retry transient GitHub failures",
                status: .open
            ),
            .init(
                identifier: PullRequestIdentifier(owner: "octo", repo: "beta", number: 12),
                title: "Draft: split the scheduler coordinator",
                status: .draft
            ),
            .init(
                identifier: PullRequestIdentifier(owner: "other", repo: "gamma", number: 340),
                title: "Fix the pending review race",
                status: .merged
            ),
            .init(
                identifier: PullRequestIdentifier(owner: "other", repo: "delta", number: 2),
                title: "Revert the cache change",
                status: .closed
            )
        ]
        return HostToolWidgetEntry(
            id: "tool-list-prs",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.listToolName),
            content: .pullRequestList(
                PullRequestListWidgetContent(
                    filter: .all,
                    rows: rows,
                    totalCount: rows.count,
                    hasWarnings: false,
                    message: nil,
                    status: .listed
                )
            ),
            isComplete: true
        )
    }
}
