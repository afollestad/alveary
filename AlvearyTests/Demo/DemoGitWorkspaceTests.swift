#if DEBUG
import XCTest

@testable import Alveary

/// Guards the invariants each canned Git workspace has to hold for the diff surface to stay
/// self-consistent: the toolbar badge, the pane's file list, and the rendered hunks all come from
/// one workspace, so they must describe the same change.
final class DemoGitWorkspaceTests: XCTestCase {
    func testStatsEqualTheParsedSumOfPerPathDiffs() {
        for workspace in DemoGitWorkspaces.all {
            var additions = 0
            var deletions = 0
            for diff in workspace.diffsByPath.values {
                let files = DiffParser.parse(diff)
                XCTAssertFalse(files.isEmpty, "\(workspace.path) serves a diff that parses to nothing")
                additions += files.reduce(0) { $0 + $1.linesAdded }
                deletions += files.reduce(0) { $0 + $1.linesDeleted }
            }
            // The toolbar badge and the pane's file rows render side by side; the real pipeline
            // sums tracked hunks plus untracked additions the same way.
            XCTAssertEqual(workspace.stats.additions, additions, workspace.path)
            XCTAssertEqual(workspace.stats.deletions, deletions, workspace.path)
        }
    }

    func testEveryStatusRowServesADiff() {
        for workspace in DemoGitWorkspaces.all {
            XCTAssertEqual(
                Set(workspace.statuses.map(\.path)),
                Set(workspace.diffsByPath.keys),
                "\(workspace.path) lists a file the pane cannot render, or serves a diff no row requests"
            )
        }
    }

    /// Real git semantics: a whole-scope diff carries every change except unstaged untracked
    /// files, which only reach the pane through `syntheticAddedDiff`. A file added to
    /// `diffsByPath` but forgotten in `combinedDiff` (or vice versa) breaks whole-scope requests
    /// silently, so compare their parsed totals.
    func testCombinedDiffCarriesEveryTrackedChange() {
        for workspace in DemoGitWorkspaces.all {
            var additions = 0
            var deletions = 0
            for status in workspace.statuses where !(status.status == .untracked && !status.isStaged) {
                let files = DiffParser.parse(workspace.diffsByPath[status.path] ?? "")
                additions += files.reduce(0) { $0 + $1.linesAdded }
                deletions += files.reduce(0) { $0 + $1.linesDeleted }
            }
            let combined = DiffParser.parse(workspace.combinedDiff)
            XCTAssertEqual(combined.reduce(0) { $0 + $1.linesAdded }, additions, workspace.path)
            XCTAssertEqual(combined.reduce(0) { $0 + $1.linesDeleted }, deletions, workspace.path)
        }
    }

    func testHunkHeaderCountsMatchTheirBodies() {
        for workspace in DemoGitWorkspaces.all {
            for (path, diff) in workspace.diffsByPath {
                for file in DiffParser.parse(diff) {
                    for hunk in file.hunks {
                        let old = hunk.lines.count { $0.type == .deleted || $0.type == .context }
                        let new = hunk.lines.count { $0.type == .added || $0.type == .context }
                        XCTAssertEqual(hunk.oldCount, old, "\(path) @@ -\(hunk.oldStart)")
                        XCTAssertEqual(hunk.newCount, new, "\(path) @@ +\(hunk.newStart)")
                    }
                }
            }
        }
    }
}
#endif
