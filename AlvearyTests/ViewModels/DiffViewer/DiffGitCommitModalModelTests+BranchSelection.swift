import XCTest

@testable import Alveary

@MainActor
extension DiffGitCommitModalModelTests {
    func testDefaultsToBaseBranchWhenCurrentBranchMatchesBase() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("main")
        )
        let model = makeModel(gitService: gitService)

        await model.load()

        XCTAssertEqual(model.branchSelection, .base)
        XCTAssertEqual(model.selectedBranchTitle, "main")
    }

    /// The repository's default branch wins over the context's persisted hint,
    /// so the "you are on base" gate fires on the branch that is actually the
    /// base rather than whichever one was checked out at project import.
    func testPrefersTheResolvedDefaultBranchOverTheContextHint() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("trunk"),
            defaultBranchResult: "trunk"
        )
        let model = makeModel(gitService: gitService)

        await model.load()

        XCTAssertEqual(model.baseBranch, "trunk")
        XCTAssertEqual(model.branchSelection, .base)
        XCTAssertEqual(model.selectedBranchTitle, "trunk")
    }

    func testBaseBranchFallsBackToTheContextWhenNoDefaultResolves() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("main")
        )
        let model = makeModel(gitService: gitService)

        await model.load()

        XCTAssertEqual(model.baseBranch, "main")
    }

    func testDefaultsToCurrentBranchWhenCurrentBranchDiffersFromBase() async {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        let settingsService = InMemorySettingsService(current: settings)
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("feature/current")
        )
        let model = makeModel(
            targetName: "Disable Steering During Handoff",
            gitService: gitService,
            settingsService: settingsService
        )

        await model.load()

        XCTAssertEqual(model.branchSelection, .current)
        XCTAssertEqual(model.selectedBranchTitle, "feature/current")
        XCTAssertTrue(model.isCurrentBranchSelectable)
        XCTAssertNil(model.preflightMessage)
        // The name is still prepared so switching to New branch has a default.
        XCTAssertEqual(model.newBranchName, "af/disable-steering-during-handoff")
    }

    func testCurrentBranchIsNotOfferedWhenAlreadyOnBase() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("main")
        )
        let model = makeModel(gitService: gitService)

        await model.load()

        XCTAssertFalse(model.isCurrentBranchSelectable)
    }

    func testCommittingToCurrentBranchDoesNotCheckOutANewBranch() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            currentBranchResult: .success("feature/current")
        )
        let model = makeModel(gitService: gitService)
        model.commitMessage = "Adjust the header"

        await model.load()
        let didCommit = await model.perform(commitAndPush: false)

        XCTAssertTrue(didCommit)
        let checkoutNewBranchCalls = await gitService.checkoutNewBranchCalls()
        let commitCalls = await gitService.commitCalls()
        XCTAssertTrue(checkoutNewBranchCalls.isEmpty)
        XCTAssertEqual(commitCalls.first?.message, "Adjust the header")
        XCTAssertEqual(model.currentBranch, "feature/current")
    }
}
