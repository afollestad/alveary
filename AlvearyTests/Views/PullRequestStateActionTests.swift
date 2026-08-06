import XCTest

@testable import Alveary

/// The review footer's state-change policy: permission, merged pull requests, the
/// deleted head branch that blocks reopening, and the node-id-gated draft actions
/// in both directions.
final class PullRequestStateActionTests: XCTestCase {
    private func detail(
        status: PullRequestStatus,
        viewerCanUpdate: Bool = true,
        headRefExists: Bool = true,
        headRefName: String = "feat/change",
        nodeID: String? = "PR_41"
    ) -> PullRequestDetail {
        var detail = PullRequestDetail(
            id: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            title: "Improve parser",
            url: nil,
            status: status,
            authorLogin: "alice",
            authorAvatarURL: nil,
            headRefName: headRefName,
            baseRefName: "main",
            createdAt: nil,
            updatedAt: nil,
            additions: 1,
            deletions: 0,
            changedFiles: 1,
            bodyMarkdown: "",
            reviewDecision: nil,
            checks: [],
            comments: [],
            reviews: [],
            reviewThreads: [],
            viewerCanUpdate: viewerCanUpdate,
            headRefExists: headRefExists
        )
        detail.nodeID = nodeID
        return detail
    }

    private func loadedDetail(status: PullRequestStatus) -> PullRequestDetail {
        detail(status: status)
    }

    func testMissingDetailHasNoActions() {
        XCTAssertEqual(PullRequestStateAction.available(for: nil), [])
    }

    func testWithoutWritePermissionHasNoActions() {
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .open, viewerCanUpdate: false)), [])
    }

    func testMergedPullRequestHasNoActions() {
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .merged)), [])
    }

    func testOpenPullRequestLeadsWithCloseThenMarkDraft() {
        let actions = PullRequestStateAction.available(for: detail(status: .open))
        XCTAssertEqual(actions.map(\.kind), [.close, .markDraft])
        XCTAssertEqual(actions.map(\.title), ["Close PR", "Mark as draft"])
        XCTAssertEqual(actions.map(\.isEnabled), [true, true])
        XCTAssertNil(actions.first?.disabledNote)
        XCTAssertNil(actions.last?.disabledNote)
    }

    func testOpenWithoutNodeIDCannotMarkDraft() {
        // The mutation is addressed by node id, exactly like leaving draft.
        let actions = PullRequestStateAction.available(for: detail(status: .open, nodeID: nil))
        XCTAssertEqual(actions.map(\.kind), [.close])
    }

    func testDraftLeadsWithMarkReadyThenClose() {
        let actions = PullRequestStateAction.available(for: detail(status: .draft))
        XCTAssertEqual(actions.map(\.kind), [.markReady, .close])
        XCTAssertEqual(actions.first?.title, "Ready for review")
        XCTAssertEqual(actions.first?.isEnabled, true)
    }

    func testDraftWithoutNodeIDCannotMarkReady() {
        // The mutation is addressed by node id; without one the option is absent
        // rather than offered and failing.
        let actions = PullRequestStateAction.available(for: detail(status: .draft, nodeID: nil))
        XCTAssertEqual(actions.map(\.kind), [.close])
    }

    func testPlaceholderIsDisabledAndTitledLikeTheEventualDefault() {
        // The stand-in keeps the footer's even split while the detail loads, so
        // its title must match what the loaded action will say.
        let expected: [PullRequestStatus: PullRequestStateAction.Kind] = [
            .open: .close,
            .closed: .reopen,
            .draft: .markReady
        ]
        for (status, kind) in expected {
            let placeholder = PullRequestStateAction.placeholder(for: status)
            XCTAssertEqual(placeholder?.kind, kind)
            XCTAssertEqual(placeholder?.title, PullRequestStateAction.available(for: loadedDetail(status: status)).first?.title)
            XCTAssertEqual(placeholder?.isEnabled, false)
            XCTAssertNil(placeholder?.disabledNote)
        }
    }

    func testOnlyClosingIsDestructive() {
        // Red is reserved for the action that throws work away; the placeholder
        // follows the same rule so the color survives the detail landing.
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .open)).first?.isDestructive, true)
        XCTAssertEqual(PullRequestStateAction.placeholder(for: .open)?.isDestructive, true)
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .closed)).first?.isDestructive, false)
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .draft)).first?.isDestructive, false)
        // Mark as draft rides beside Close PR in the split button and must not
        // inherit its red when the menu promotes it to the primary side.
        XCTAssertEqual(PullRequestStateAction.available(for: detail(status: .open)).last?.isDestructive, false)
    }

    func testMergedHasNoPlaceholder() {
        XCTAssertNil(PullRequestStateAction.placeholder(for: .merged))
    }

    func testClosedWithLiveBranchReopens() {
        let actions = PullRequestStateAction.available(for: detail(status: .closed))
        XCTAssertEqual(actions.map(\.kind), [.reopen])
        XCTAssertEqual(actions.first?.title, "Reopen PR")
        XCTAssertEqual(actions.first?.isEnabled, true)
        XCTAssertNil(actions.first?.disabledNote)
    }

    func testClosedWithDeletedBranchDisablesReopenAndNamesTheBranch() {
        let actions = PullRequestStateAction.available(for: detail(status: .closed, headRefExists: false))
        XCTAssertEqual(actions.map(\.kind), [.reopen])
        XCTAssertEqual(actions.first?.isEnabled, false)
        XCTAssertEqual(actions.first?.disabledNote, "The feat/change branch has been deleted.")
    }

    func testDeletedBranchWithoutANameFallsBackToTheGenericNote() {
        let actions = PullRequestStateAction.available(
            for: detail(status: .closed, headRefExists: false, headRefName: "")
        )
        XCTAssertEqual(actions.first?.disabledNote, "The head branch has been deleted.")
    }
}
