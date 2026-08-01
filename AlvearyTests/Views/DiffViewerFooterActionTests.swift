import XCTest

@testable import Alveary

/// The footer ladder policy: default-first ordering is the state machine, and
/// every still-valid action stays reachable behind the leader.
final class DiffViewerFooterActionTests: XCTestCase {
    func testDirtyTreeLeadsWithCommitAndKeepsValidRungsBehindIt() {
        let actions = DiffViewerFooterAction.available(
            workingState: DiffViewerWorkingState(hasChanges: true, hasUnpushedCommits: true),
            canCommit: true,
            canCreatePullRequest: true,
            canViewPullRequest: false
        )

        XCTAssertEqual(actions.map(\.kind), [.commit, .push, .createPullRequest])
        XCTAssertEqual(actions.map(\.title), ["Commit", "Push changes", "Create PR"])
        XCTAssertTrue(actions.allSatisfy(\.isEnabled))
    }

    func testCleanTreeWithUnpushedCommitsLeadsWithPush() {
        let actions = DiffViewerFooterAction.available(
            workingState: DiffViewerWorkingState(hasChanges: false, hasUnpushedCommits: true),
            canCommit: true,
            canCreatePullRequest: true,
            canViewPullRequest: false
        )

        XCTAssertEqual(actions.map(\.kind), [.push, .createPullRequest])
    }

    func testCleanPushedTreeOffersCreateOrViewAlone() {
        let create = DiffViewerFooterAction.available(
            workingState: .none,
            canCommit: true,
            canCreatePullRequest: true,
            canViewPullRequest: false
        )
        XCTAssertEqual(create.map(\.kind), [.createPullRequest])

        let view = DiffViewerFooterAction.available(
            workingState: .none,
            canCommit: true,
            canCreatePullRequest: false,
            canViewPullRequest: true
        )
        XCTAssertEqual(view.map(\.kind), [.viewPullRequest])
    }

    /// Several linked pull requests leave neither create nor view; a clean,
    /// pushed tree then has no action at all and the footer renders the
    /// disabled placeholder.
    func testNothingAvailableWhenCleanPushedAndSeverallyLinked() {
        let actions = DiffViewerFooterAction.available(
            workingState: .none,
            canCommit: true,
            canCreatePullRequest: false,
            canViewPullRequest: false
        )

        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(DiffViewerFooterAction.placeholder.kind, .commit)
        XCTAssertFalse(DiffViewerFooterAction.placeholder.isEnabled)
    }

    /// Commit and Push share the working-tree mutation gate; a selection that
    /// cannot commit (a Task-mode thread) offers neither, while View PR — a
    /// pure navigation — survives.
    func testCommitAndPushRequireTheCommitGate() {
        let actions = DiffViewerFooterAction.available(
            workingState: DiffViewerWorkingState(hasChanges: true, hasUnpushedCommits: true),
            canCommit: false,
            canCreatePullRequest: false,
            canViewPullRequest: true
        )

        XCTAssertEqual(actions.map(\.kind), [.viewPullRequest])
    }
}
