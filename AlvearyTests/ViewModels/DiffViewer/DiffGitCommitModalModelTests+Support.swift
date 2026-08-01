import XCTest

@testable import Alveary

extension DiffGitCommitModalModelTests {
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

actor DiffGitCommitModalMockGitService: GitService {
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
    private let commitsAheadResult: Result<Int, Error>
    private let commitsAheadDetailsResult: Result<[CommitInfo], Error>
    private let diffForCommitResults: [String: String]
    private let hasUnpushedCommitsResult: Result<Bool, Error>
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
        currentBranchResult: Result<String, Error> = .success("main"),
        commitsAheadResult: Result<Int, Error> = .success(0),
        commitsAheadDetailsResult: Result<[CommitInfo], Error> = .success([]),
        diffForCommitResults: [String: String] = [:],
        hasUnpushedCommitsResult: Result<Bool, Error> = .success(false)
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
        self.commitsAheadResult = commitsAheadResult
        self.commitsAheadDetailsResult = commitsAheadDetailsResult
        self.diffForCommitResults = diffForCommitResults
        self.hasUnpushedCommitsResult = hasUnpushedCommitsResult
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
        try commitsAheadResult.get()
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        try commitsAheadDetailsResult.get()
    }

    func diffForCommit(hash: String, in directory: String) async throws -> String {
        diffForCommitResults[hash] ?? ""
    }

    func hasUnpushedCommits(baseBranch: String, remoteName: String?, in directory: String) async throws -> Bool {
        try hasUnpushedCommitsResult.get()
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

struct ModalTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
