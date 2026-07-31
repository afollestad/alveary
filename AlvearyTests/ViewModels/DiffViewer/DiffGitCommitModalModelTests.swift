import XCTest

@testable import Alveary

@MainActor
final class DiffGitCommitModalModelTests: XCTestCase {
    func testIncludeUnstagedTogglePersistsImmediately() {
        var settings = AppSettings()
        settings.gitCommitIncludeUnstagedChanges = true
        let settingsService = InMemorySettingsService(current: settings)
        let model = makeModel(settingsService: settingsService)

        model.includeUnstagedChanges = false

        XCTAssertFalse(settingsService.current.gitCommitIncludeUnstagedChanges)
    }

    func testStagedOnlyWithoutStagedChangesDisablesActions() async {
        var settings = AppSettings()
        settings.gitCommitIncludeUnstagedChanges = false
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            hasStagedChangesResults: [.success(false)],
            currentBranchResult: .success("main")
        )
        let model = makeModel(
            gitService: gitService,
            settingsService: InMemorySettingsService(current: settings)
        )

        await model.load()

        XCTAssertEqual(model.preflightMessage, "No staged changes to commit.")
        XCTAssertTrue(model.commitButtonDisabled)
        XCTAssertTrue(model.primaryActionButtonDisabled)
    }

    func testBlankMessageGeneratesPromptAndCommitsGeneratedMessage() async throws {
        var settings = AppSettings()
        settings.gitCommitIncludeUnstagedChanges = false
        settings.commitMessageGenerationPrompt = "Use the repo commit style."
        let stagedFile = FileStatus(path: "Sources/App.swift", originalPath: nil, status: .modified, isStaged: true)
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [.success([stagedFile])],
            diffResultQueue: [.success("diff --git a/Sources/App.swift b/Sources/App.swift")],
            hasStagedChangesResults: [.success(true), .success(true)],
            currentBranchResult: .success("main")
        )
        var capturedPrompt = ""
        let model = makeModel(
            gitService: gitService,
            settingsService: InMemorySettingsService(current: settings),
            generateCommitMessage: { prompt in
                capturedPrompt = prompt
                return "Add `DiffGitCommitModal`\n\nCo-authored-by: Codex <noreply@openai.com>"
            }
        )

        await model.load()
        let didComplete = await model.perform(commitAndPush: false)

        XCTAssertTrue(didComplete)
        XCTAssertTrue(capturedPrompt.contains("**STAGED**"))
        XCTAssertTrue(capturedPrompt.contains("Use the repo commit style."))
        XCTAssertTrue(capturedPrompt.contains("## Staged Diff"))
        let commitCalls = await gitService.commitCalls()
        XCTAssertEqual(commitCalls.count, 1)
        XCTAssertEqual(commitCalls[0].message, "Add `DiffGitCommitModal`\n\nCo-authored-by: Codex <noreply@openai.com>")
        XCTAssertFalse(commitCalls[0].includeUnstagedChanges)
    }

    func testNewBranchCheckoutRunsBeforeCommit() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            validateBranchNameResults: [.success(true)],
            currentBranchResult: .success("feature/current")
        )
        let model = makeModel(gitService: gitService)
        model.commitMessage = "Commit directly"

        await model.load()
        // Off-base now defaults to the current branch, so the New-branch path
        // this test covers has to be chosen explicitly.
        model.selectNewBranch()
        let didComplete = await model.perform(commitAndPush: false)

        XCTAssertTrue(didComplete)
        let validateBranchNameCalls = await gitService.validateBranchNameCalls()
        let checkoutNewBranchCalls = await gitService.checkoutNewBranchCalls()
        let commitCalls = await gitService.commitCalls()
        XCTAssertEqual(validateBranchNameCalls.first?.branchName, "alveary/test-thread")
        XCTAssertEqual(checkoutNewBranchCalls.first?.branchName, "alveary/test-thread")
        XCTAssertEqual(commitCalls.first?.message, "Commit directly")
    }

    func testNewBranchRetryAfterCommitFailureDoesNotCheckoutAgain() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            commitResults: [
                .failure(ModalTestError("Commit failed")),
                .success(())
            ],
            currentBranchResult: .success("feature/current")
        )
        let model = makeModel(gitService: gitService)
        model.commitMessage = "Commit directly"

        await model.load()
        model.selectNewBranch()
        let firstAttempt = await model.perform(commitAndPush: false)
        let secondAttempt = await model.perform(commitAndPush: false)

        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(secondAttempt)
        let checkoutNewBranchCalls = await gitService.checkoutNewBranchCalls()
        let commitCalls = await gitService.commitCalls()
        XCTAssertEqual(checkoutNewBranchCalls.count, 1)
        XCTAssertEqual(commitCalls.count, 2)
    }

    func testCommitAndPushReportsPushFailureAfterCommitWithoutClosing() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            pushResults: [.failure(ModalTestError("Rejected by remote"))],
            currentBranchResult: .success("main")
        )
        var refreshCount = 0
        let model = makeModel(
            gitService: gitService,
            refreshAfterMutation: {
                refreshCount += 1
            }
        )
        model.commitMessage = "Commit directly"

        await model.load()
        let didComplete = await model.perform(commitAndPush: true)

        XCTAssertFalse(didComplete)
        XCTAssertEqual(refreshCount, 1)
        let commitCalls = await gitService.commitCalls()
        let pushCalls = await gitService.pushCalls()
        XCTAssertEqual(commitCalls.count, 1)
        XCTAssertEqual(pushCalls.first?.remoteName, "origin")
        XCTAssertFalse(model.forcePushRequired)
        XCTAssertEqual(model.primaryActionButtonTitle, "Commit and push")
        XCTAssertTrue(model.commitButtonDisabled)
        XCTAssertTrue(model.primaryActionButtonDisabled)
        XCTAssertEqual(model.errorMessage, "Commit succeeded, but push failed: Rejected by remote")

        let retryCompleted = await model.perform(commitAndPush: true)
        let commitCallsAfterRetry = await gitService.commitCalls()

        XCTAssertFalse(retryCompleted)
        XCTAssertEqual(commitCallsAfterRetry.count, 1)
    }

    func testCommitAndPushSwitchesToForcePushAfterNonFastForwardRejection() async {
        let gitService = DiffGitCommitModalMockGitService(
            statusResults: [],
            pushResults: [.failure(GitError.nonFastForwardPushRequired("Rejected (non-fast-forward)"))],
            currentBranchResult: .success("main")
        )
        var refreshCount = 0
        let model = makeModel(
            gitService: gitService,
            refreshAfterMutation: {
                refreshCount += 1
            }
        )
        model.commitMessage = "Commit directly"

        await model.load()
        let didComplete = await model.perform(commitAndPush: true)

        XCTAssertFalse(didComplete)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertTrue(model.didCommitSuccessfully)
        XCTAssertTrue(model.forcePushRequired)
        XCTAssertEqual(model.errorMessage, "Force push required.")
        XCTAssertTrue(model.controlsDisabled)
        XCTAssertTrue(model.commitButtonDisabled)
        XCTAssertFalse(model.primaryActionButtonDisabled)
        XCTAssertEqual(model.primaryActionButtonTitle, "Force push")

        let commitCalls = await gitService.commitCalls()
        let pushCalls = await gitService.pushCalls()
        let forcePushCalls = await gitService.forcePushCalls()
        XCTAssertEqual(commitCalls.count, 1)
        XCTAssertEqual(pushCalls.count, 1)
        XCTAssertEqual(pushCalls.first?.remoteName, "origin")
        XCTAssertTrue(forcePushCalls.isEmpty)

        let forcePushCompleted = await model.performPrimaryAction()

        XCTAssertTrue(forcePushCompleted)
        XCTAssertEqual(refreshCount, 2)
        XCTAssertFalse(model.forcePushRequired)
        let commitCallsAfterForcePush = await gitService.commitCalls()
        let forcePushCallsAfterForcePush = await gitService.forcePushCalls()
        XCTAssertEqual(commitCallsAfterForcePush.count, 1)
        XCTAssertEqual(forcePushCallsAfterForcePush.first?.remoteName, "origin")
    }
}
