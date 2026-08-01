import SwiftUI
import XCTest

@testable import Alveary

/// `DiffViewerPaneHeader` layout: the mode chips, the action row, and the
/// trailing close button. Split out of `SnapshotTests+DiffViewer.swift` to keep
/// that file under the length limit.
extension SnapshotTests {
    func testDiffViewerPaneHeaderMixedSelectionActions() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .currentChanges,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 520, height: 72),
            named: "diff_viewer_header_mixed_selection"
        )
    }

    /// The narrowest the right pane can be resized to
    /// (`AppSettings.supportedRightPaneWidthRange.lowerBound`), carrying every
    /// action at once. The chip row and the action strip together exceed that
    /// width, so this is the baseline that catches the header overflowing.
    func testDiffViewerPaneHeaderMinimumWidthAllActions() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                mode: .currentChanges,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {}
            ),
            size: CGSize(width: 320, height: 72),
            named: "diff_viewer_header_minimum_width_all_actions"
        )
    }

    /// The default pane width with the ordinary single action — what the header
    /// looks like almost all the time.
    func testDiffViewerPaneHeaderDefaultWidthWithClose() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                branchName: "main",
                mode: .currentChanges,
                selectedFiles: [],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {},
                onClose: {}
            ),
            size: CGSize(width: 380, height: 72),
            named: "diff_viewer_header_default_width_with_close"
        )
    }

    /// The close button consumes header width the action row used to have, and
    /// this header silently clips its trailing action rather than compressing —
    /// so the narrowest pane has to be re-checked with the button present.
    func testDiffViewerPaneHeaderMinimumWidthAllActionsWithClose() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                branchName: "main",
                mode: .currentChanges,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {},
                onClose: {}
            ),
            size: CGSize(width: 320, height: 72),
            named: "diff_viewer_header_minimum_width_all_actions_with_close"
        )
    }

    /// The branch label is the header's only flexible child, so a long name must
    /// truncate at its cap instead of pushing the action row off the pane.
    func testDiffViewerPaneHeaderLongBranchNameTruncates() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                branchName: "alveary/a-deliberately-overlong-feature-branch-name",
                mode: .currentChanges,
                selectedFiles: [],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {},
                onClose: {}
            ),
            size: CGSize(width: 380, height: 72),
            named: "diff_viewer_header_long_branch_name"
        )
    }

    /// The narrowest pane, carrying a long branch name *and* every action — the
    /// case where the branch label competes hardest with the action row. The
    /// label must yield rather than clip an action away.
    func testDiffViewerPaneHeaderMinimumWidthLongBranchName() {
        assertMacSnapshot(
            DiffViewerPaneHeader(
                activeDirectory: "/tmp/alveary",
                branchName: "alveary/a-deliberately-overlong-feature-branch-name",
                mode: .currentChanges,
                selectedFiles: [
                    FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: false),
                    FileStatus(path: "Tests/AppTests.swift", originalPath: nil, status: .modified, isStaged: true)
                ],
                showsFileListDivider: false,
                showsFileActions: true,
                onModeSelected: { _ in },
                onStageSelectedFiles: {},
                onUnstageSelectedFiles: {},
                onDiscardSelectedFiles: {},
                onClose: {}
            ),
            size: CGSize(width: 320, height: 72),
            named: "diff_viewer_header_minimum_width_long_branch_name"
        )
    }
}
