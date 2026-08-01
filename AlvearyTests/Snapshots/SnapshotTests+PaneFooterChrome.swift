import SwiftUI
import XCTest

@testable import Alveary

// Parity gate for `contextualPaneFooterChrome()`. The shared `ContextualPaneFooter`
// and the hand-composed pull-request review footer must render the same insets,
// bar fill, and top hairline; a surface that re-hand-rolls its padding shows up
// here as a visible step between the two strips.
extension SnapshotTests {
    func testPaneFooterChromeParity() {
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 0)

        let stacked = VStack(spacing: 0) {
            ContextualPaneFooter {
                Button("Cancel") {}
                    .secondaryActionButtonStyle(expandsHorizontally: true)
            } trailingAction: {
                Button("Save") {}
                    .primaryActionButtonStyle(expandsHorizontally: true)
            }

            fixture.footer(initiallyExpanded: false)

            DiffViewerPaneFooter(
                actions: DiffViewerFooterAction.available(
                    workingState: DiffViewerWorkingState(hasChanges: true, hasUnpushedCommits: true),
                    canCommit: true,
                    canCreatePullRequest: true,
                    canViewPullRequest: false
                ),
                isPerformingAction: false,
                onAction: { _ in }
            )
        }
        .frame(width: 460)

        assertMacSnapshot(
            stacked,
            size: CGSize(width: 460, height: 224),
            named: "pane_footer_chrome_parity"
        )
    }
}
