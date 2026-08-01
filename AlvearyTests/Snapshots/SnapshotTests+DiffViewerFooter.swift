import SwiftUI
import XCTest

@testable import Alveary

/// One baseline per rung of the Git changes footer's action ladder, plus the
/// zero-available placeholder.
extension SnapshotTests {
    func testDiffViewerFooterCommitLeadsWithCaret() {
        assertDiffViewerFooterSnapshot(
            workingState: DiffViewerWorkingState(hasChanges: true, hasUnpushedCommits: true),
            canCreatePullRequest: true,
            canViewPullRequest: false,
            named: "diff_viewer_footer_commit_split"
        )
    }

    func testDiffViewerFooterPushLeads() {
        assertDiffViewerFooterSnapshot(
            workingState: DiffViewerWorkingState(hasChanges: false, hasUnpushedCommits: true),
            canCreatePullRequest: true,
            canViewPullRequest: false,
            named: "diff_viewer_footer_push_split"
        )
    }

    func testDiffViewerFooterCreatePullRequestAlone() {
        assertDiffViewerFooterSnapshot(
            workingState: .none,
            canCreatePullRequest: true,
            canViewPullRequest: false,
            named: "diff_viewer_footer_create_pr"
        )
    }

    func testDiffViewerFooterViewPullRequestAlone() {
        assertDiffViewerFooterSnapshot(
            workingState: .none,
            canCreatePullRequest: false,
            canViewPullRequest: true,
            named: "diff_viewer_footer_view_pr"
        )
    }

    func testDiffViewerFooterPlaceholderWhenNothingIsAvailable() {
        assertDiffViewerFooterSnapshot(
            workingState: .none,
            canCreatePullRequest: false,
            canViewPullRequest: false,
            named: "diff_viewer_footer_placeholder"
        )
    }

    /// Forwards `#function` so baselines carry the test's name, not this helper's.
    private func assertDiffViewerFooterSnapshot(
        workingState: DiffViewerWorkingState,
        canCreatePullRequest: Bool,
        canViewPullRequest: Bool,
        named name: String,
        testName: String = #function
    ) {
        assertMacSnapshot(
            DiffViewerPaneFooter(
                actions: DiffViewerFooterAction.available(
                    workingState: workingState,
                    canCommit: true,
                    canCreatePullRequest: canCreatePullRequest,
                    canViewPullRequest: canViewPullRequest
                ),
                isPerformingAction: false,
                onAction: { _ in }
            ),
            size: CGSize(width: 380, height: 64),
            named: name,
            testName: testName
        )
    }
}
