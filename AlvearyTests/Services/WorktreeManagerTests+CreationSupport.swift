import Foundation

@testable import Alveary

@MainActor
extension WorktreeManagerTests {
    func makeSetupScriptCreationFixture() async throws -> WorktreeSetupCreationFixture {
        let projectURL = try makeTemporaryProject()
        let worktreesBaseURL = try makeTemporaryWorktreesBase()
        try writeProjectConfig(
            at: projectURL,
            json: """
            {
              "scripts": {
                "setup": "echo setup",
                "setupTimeoutSeconds": 45
              },
              "preservePatterns": [".env.local", "config/*.json"]
            }
            """
        )
        try "API_KEY=1".write(to: projectURL.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: projectURL.appendingPathComponent("config"), withIntermediateDirectories: true)
        try "{}".write(to: projectURL.appendingPathComponent("config/dev.json"), atomically: true, encoding: .utf8)

        let shell = MockShellRunner()
        let expectedBranch = "af-fix-auth-bug-59c-2"
        let expectedWorktreePath = namespacedWorktreesDirectory(
            for: projectURL,
            base: worktreesBaseURL
        ).appendingPathComponent("fix-auth-bug-59c-2").path
        await enqueueSetupScriptResponses(
            on: shell,
            expectedBranch: expectedBranch,
            expectedWorktreePath: expectedWorktreePath
        )

        var settings = AppSettings()
        settings.branchPrefix = "af-"
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        return WorktreeSetupCreationFixture(
            projectURL: projectURL,
            shell: shell,
            manager: DefaultWorktreeManager(
                settingsService: InMemorySettingsService(current: settings),
                shell: shell
            )
        )
    }

    func makeFailedSetupCreationFixture() async throws -> FailedSetupWorktreeCreationFixture {
        let projectURL = try makeTemporaryProject()
        let worktreesBaseURL = try makeTemporaryWorktreesBase()
        try writeProjectConfig(
            at: projectURL,
            json: """
            {
              "scripts": {
                "setup": "exit 1"
              }
            }
            """
        )

        let shell = MockShellRunner()
        let expectedBranch = "alveary/broken-setup-\(shortHash("Broken setup"))"
        let expectedWorktreePath = namespacedWorktreesDirectory(
            for: projectURL,
            base: worktreesBaseURL
        ).appendingPathComponent(String(expectedBranch.dropFirst("alveary/".count))).path
        await enqueueFailedSetupResponses(
            on: shell,
            expectedBranch: expectedBranch,
            expectedWorktreePath: expectedWorktreePath
        )

        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        return FailedSetupWorktreeCreationFixture(
            projectURL: projectURL,
            expectedBranch: expectedBranch,
            shell: shell,
            manager: DefaultWorktreeManager(
                settingsService: InMemorySettingsService(current: settings),
                shell: shell
            )
        )
    }

    private func enqueueSetupScriptResponses(
        on shell: MockShellRunner,
        expectedBranch: String,
        expectedWorktreePath: String
    ) async {
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.failingShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(
            .success(
                Self.worktreeListResult(
                    worktreePath: expectedWorktreePath,
                    branch: expectedBranch,
                    headOID: WorktreeTestObjectID.worktree
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
    }

    private func enqueueFailedSetupResponses(
        on shell: MockShellRunner,
        expectedBranch: String,
        expectedWorktreePath: String
    ) async {
        await shell.enqueue(.success(Self.failingShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(
            .success(
                Self.worktreeListResult(
                    worktreePath: expectedWorktreePath,
                    branch: expectedBranch,
                    headOID: WorktreeTestObjectID.worktree
                )
            )
        )
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "boom",
                    exitCode: 1,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(
            .success(
                Self.worktreeListResult(
                    worktreePath: expectedWorktreePath,
                    branch: expectedBranch,
                    headOID: WorktreeTestObjectID.worktree
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
    }
}

@MainActor
struct WorktreeSetupCreationFixture {
    let projectURL: URL
    let shell: MockShellRunner
    let manager: DefaultWorktreeManager
}

@MainActor
struct FailedSetupWorktreeCreationFixture {
    let projectURL: URL
    let expectedBranch: String
    let shell: MockShellRunner
    let manager: DefaultWorktreeManager
}
