import XCTest

@testable import Alveary

@MainActor
final class DiffGitCommitModalModelTests: XCTestCase {
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

    func testDefaultsToNewBranchWhenCurrentBranchDiffersFromBase() async {
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

        XCTAssertEqual(model.branchSelection, .new)
        XCTAssertEqual(model.newBranchName, "af/disable-steering-during-handoff")
    }

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

private extension DiffGitCommitModalModelTests {
    func makeModel(
        targetName: String = "Test Thread",
        gitService: GitService = DiffGitCommitModalMockGitService(statusResults: []),
        settingsService: InMemorySettingsService = InMemorySettingsService(),
        generateCommitMessage: @escaping @MainActor (String) async throws -> String = { _ in "Generated commit" },
        refreshAfterMutation: @escaping @MainActor () async -> Void = {}
    ) -> DiffGitCommitModalModel {
        DiffGitCommitModalModel(
            context: DiffGitCommitModalContext(
                directory: "/tmp/alveary-project",
                targetName: targetName,
                baseBranch: "main",
                remoteName: "origin"
            ),
            gitService: gitService,
            settingsService: settingsService,
            generateCommitMessage: generateCommitMessage,
            refreshAfterMutation: refreshAfterMutation
        )
    }
}

private actor DiffGitCommitModalMockGitService: GitService {
    struct DiffCall: Equatable {
        let paths: [String]
        let scope: DiffScope
        let directory: String
    }

    struct BranchCall: Equatable {
        let branchName: String
        let directory: String
    }

    struct CommitCall: Equatable {
        let message: String
        let includeUnstagedChanges: Bool
        let directory: String
    }

    struct PushCall: Equatable {
        let remoteName: String?
        let directory: String
    }

    private var statusResults: [Result<[FileStatus], Error>]
    private var diffStatsResults: [Result<DiffStats, Error>]
    private var diffResultQueue: [Result<String, Error>]
    private var syntheticDiffResults: [Result<String, Error>]
    private var hasStagedChangesResults: [Result<Bool, Error>]
    private var validateBranchNameResults: [Result<Bool, Error>]
    private var checkoutNewBranchResults: [Result<Void, Error>]
    private var commitResults: [Result<Void, Error>]
    private var pushResults: [Result<Void, Error>]
    private var forcePushResults: [Result<Void, Error>]
    private let currentBranchResult: Result<String, Error>
    private var recordedDiffCalls: [DiffCall] = []
    private var recordedSyntheticDiffCalls: [String] = []
    private var recordedHasStagedChangesCallCount = 0
    private var recordedValidateBranchNameCalls: [BranchCall] = []
    private var recordedCheckoutNewBranchCalls: [BranchCall] = []
    private var recordedCommitCalls: [CommitCall] = []
    private var recordedPushCalls: [PushCall] = []
    private var recordedForcePushCalls: [PushCall] = []

    init(
        statusResults: [Result<[FileStatus], Error>],
        diffStatsResults: [Result<DiffStats, Error>] = [.success(.empty)],
        diffResultQueue: [Result<String, Error>] = [],
        syntheticDiffResults: [Result<String, Error>] = [],
        hasStagedChangesResults: [Result<Bool, Error>] = [.success(true)],
        validateBranchNameResults: [Result<Bool, Error>] = [.success(true)],
        checkoutNewBranchResults: [Result<Void, Error>] = [.success(())],
        commitResults: [Result<Void, Error>] = [.success(())],
        pushResults: [Result<Void, Error>] = [.success(())],
        forcePushResults: [Result<Void, Error>] = [.success(())],
        currentBranchResult: Result<String, Error> = .success("main")
    ) {
        self.statusResults = statusResults
        self.diffStatsResults = diffStatsResults
        self.diffResultQueue = diffResultQueue
        self.syntheticDiffResults = syntheticDiffResults
        self.hasStagedChangesResults = hasStagedChangesResults
        self.validateBranchNameResults = validateBranchNameResults
        self.checkoutNewBranchResults = checkoutNewBranchResults
        self.commitResults = commitResults
        self.pushResults = pushResults
        self.forcePushResults = forcePushResults
        self.currentBranchResult = currentBranchResult
    }

    func status(in directory: String) async throws -> [FileStatus] {
        try nextResult(from: &statusResults, default: .success([])).get()
    }

    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        try nextResult(from: &diffStatsResults, default: .success(.empty)).get()
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        recordedDiffCalls.append(DiffCall(paths: paths, scope: scope, directory: directory))
        return try nextResult(from: &diffResultQueue, default: .success("")).get()
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        recordedSyntheticDiffCalls.append(path)
        return try nextResult(from: &syntheticDiffResults, default: .success("")).get()
    }

    func stage(paths: [String], in directory: String) async throws {}

    func unstage(paths: [String], in directory: String) async throws {}

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {}

    func hasStagedChanges(in directory: String) async throws -> Bool {
        recordedHasStagedChangesCallCount += 1
        return try nextResult(from: &hasStagedChangesResults, default: .success(true)).get()
    }

    func validateBranchName(_ branchName: String, in directory: String) async throws -> Bool {
        recordedValidateBranchNameCalls.append(BranchCall(branchName: branchName, directory: directory))
        return try nextResult(from: &validateBranchNameResults, default: .success(true)).get()
    }

    func checkoutNewBranch(_ branchName: String, in directory: String) async throws {
        recordedCheckoutNewBranchCalls.append(BranchCall(branchName: branchName, directory: directory))
        try nextResult(from: &checkoutNewBranchResults, default: .success(())).get()
    }

    func commit(message: String, includeUnstagedChanges: Bool, in directory: String) async throws {
        recordedCommitCalls.append(
            CommitCall(message: message, includeUnstagedChanges: includeUnstagedChanges, directory: directory)
        )
        try nextResult(from: &commitResults, default: .success(())).get()
    }

    func pushCurrentBranch(remoteName: String?, in directory: String) async throws {
        recordedPushCalls.append(PushCall(remoteName: remoteName, directory: directory))
        try nextResult(from: &pushResults, default: .success(())).get()
    }

    func forcePushCurrentBranch(remoteName: String?, in directory: String) async throws {
        recordedForcePushCalls.append(PushCall(remoteName: remoteName, directory: directory))
        try nextResult(from: &forcePushResults, default: .success(())).get()
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        try currentBranchResult.get()
    }

    func currentHeadHash(in directory: String) async throws -> String {
        "abcdef1234567890"
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        0
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        []
    }

    func diffForCommit(hash: String, in directory: String) async throws -> String {
        ""
    }

    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data {
        Data()
    }

    func diffCalls() -> [DiffCall] {
        recordedDiffCalls
    }

    func syntheticDiffCalls() -> [String] {
        recordedSyntheticDiffCalls
    }

    func hasStagedChangesCallCount() -> Int {
        recordedHasStagedChangesCallCount
    }

    func validateBranchNameCalls() -> [BranchCall] {
        recordedValidateBranchNameCalls
    }

    func checkoutNewBranchCalls() -> [BranchCall] {
        recordedCheckoutNewBranchCalls
    }

    func commitCalls() -> [CommitCall] {
        recordedCommitCalls
    }

    func pushCalls() -> [PushCall] {
        recordedPushCalls
    }

    func forcePushCalls() -> [PushCall] {
        recordedForcePushCalls
    }

    private func nextResult<Success>(
        from results: inout [Result<Success, Error>],
        default defaultResult: Result<Success, Error>
    ) -> Result<Success, Error> {
        guard !results.isEmpty else {
            return defaultResult
        }
        return results.removeFirst()
    }
}

private struct ModalTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
