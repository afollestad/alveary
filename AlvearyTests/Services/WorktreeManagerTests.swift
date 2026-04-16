import CryptoKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class WorktreeManagerTests: XCTestCase {
    func testCreateUsesSetupScriptEnvironmentAndCollisionSuffix() async throws {
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
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.failingShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        let settings = InMemorySettingsService(current: {
            var settings = AppSettings()
            settings.branchPrefix = "af"
            settings.worktreesBaseDirectory = worktreesBaseURL.path
            return settings
        }())
        let manager = DefaultWorktreeManager(settingsService: settings, shell: shell)

        let info = try await manager.create(
            projectPath: projectURL.path,
            threadName: "Fix auth bug",
            baseRef: "main",
            remoteName: "origin"
        )

        XCTAssertTrue(info.branch.hasPrefix("af/"))
        XCTAssertTrue(info.branch.hasSuffix("-2"))
        XCTAssertEqual(URL(fileURLWithPath: info.path).lastPathComponent, String(info.branch.split(separator: "/").last!))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: info.path).appendingPathComponent(".env.local").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: info.path).appendingPathComponent("config/dev.json").path))

        let invocations = await shell.invocations
        assertSetupInvocations(invocations, branch: info.branch, worktreePath: info.path)
        assertLifecycleEnvironment(
            invocations[4].environment,
            threadName: "Fix auth bug",
            branch: info.branch,
            projectPath: projectURL.path,
            worktreePath: info.path
        )
    }

    func testCreateRollsBackWorktreeAndBranchWhenSetupFails() async throws {
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
        await shell.enqueue(.success(Self.failingShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
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
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        do {
            _ = try await manager.create(
                projectPath: projectURL.path,
                threadName: "Broken setup",
                baseRef: "main",
                remoteName: "origin"
            )
            XCTFail("Expected setup failure")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Setup script failed: boom"))
        }

        let invocations = await shell.invocations
        XCTAssertEqual(Array(invocations[4].args.prefix(3)), ["worktree", "remove", "--force"])
        XCTAssertEqual(invocations[5].args.first, "branch")
        XCTAssertEqual(invocations[5].args[1], "-D")
    }

    func testRemoveRefusesMainRepositoryEvenWithTrailingSlash() async throws {
        let projectURL = try makeTemporaryProject()
        let listOutput = """
        worktree \(projectURL.path)
        HEAD abc123
        branch refs/heads/main

        worktree \(projectURL.deletingLastPathComponent().appendingPathComponent("worktrees/demo").path)
        HEAD def456
        branch refs/heads/alveary/demo
        """

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: listOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        do {
            try await manager.remove(
                projectPath: projectURL.path,
                worktreePath: projectURL.path + "/",
                branch: "main"
            )
            XCTFail("Expected refusal to remove main repo")
        } catch let error as GitError {
            XCTAssertEqual(error, .commandFailed("Refusing to remove: \(projectURL.path)/ is not a removable worktree"))
        }
    }

    func testRemoveRunsTeardownScriptForWorktrees() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreeURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees/demo")
        try writeProjectConfig(
            at: projectURL,
            json: """
            {
              "scripts": {
                "teardown": "echo teardown"
              }
            }
            """
        )

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: worktreeListOutput(
                        projectPath: projectURL.path,
                        worktreePath: worktreeURL.path,
                        branch: "alveary/demo"
                    ),
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.remove(
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path,
            branch: "alveary/demo"
        )

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["worktree", "list", "--porcelain"])
        XCTAssertEqual(invocations[1].executable, "/bin/sh")
        XCTAssertEqual(invocations[1].args, ["-c", "echo teardown"])
        XCTAssertEqual(invocations[1].directory, worktreeURL.path)
        XCTAssertEqual(invocations[1].timeout, .seconds(60))
        XCTAssertEqual(invocations[2].args, ["worktree", "remove", "--force", worktreeURL.path])
        XCTAssertEqual(invocations[3].args, ["show-ref", "--verify", "--quiet", "refs/heads/alveary/demo"])
        XCTAssertEqual(invocations[4].args, ["branch", "-D", "alveary/demo"])
        assertLifecycleEnvironment(
            invocations[1].environment,
            threadName: "demo",
            branch: "alveary/demo",
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path
        )
    }

    func testRemoveDeletesLeftoverWorktreeDirectoryButNotParent() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesParentURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees")
        let worktreeURL = worktreesParentURL.appendingPathComponent("demo")
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: worktreesParentURL) }

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: worktreeListOutput(
                        projectPath: projectURL.path,
                        worktreePath: worktreeURL.path,
                        branch: "alveary/demo"
                    ),
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.remove(
            projectPath: projectURL.path,
            worktreePath: worktreeURL.path,
            branch: "alveary/demo"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreesParentURL.path))
    }

    func testRemoveAllDeletesRegisteredWorktreesAndProjectNamespaceDirectory() async throws {
        let projectURL = try makeTemporaryProject()
        let worktreesBaseURL = projectURL.deletingLastPathComponent().appendingPathComponent("worktrees")
        let worktreeURL = worktreesBaseURL.appendingPathComponent("demo/worktree")
        let namespaceDirectory = namespacedWorktreesDirectory(for: projectURL, base: worktreesBaseURL)
        try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)

        let listOutput = """
        worktree \(projectURL.path)
        HEAD abc123
        branch refs/heads/main

        worktree \(worktreeURL.path)
        HEAD def456
        branch refs/heads/alveary/demo
        """

        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: listOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))
        await shell.enqueue(.success(Self.emptyShellResult()))

        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        try await manager.removeAll(projectPath: projectURL.path)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.args), [
            ["worktree", "list", "--porcelain"],
            ["worktree", "remove", "--force", worktreeURL.path],
            ["show-ref", "--verify", "--quiet", "refs/heads/alveary/demo"],
            ["branch", "-D", "alveary/demo"]
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: namespaceDirectory.path))
    }

    func testRemoveAllRemovesNamespacedWorktreesWhenProjectFolderIsAlreadyGone() async throws {
        let parentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missingProjectURL = parentURL.appendingPathComponent("missing-project")
        let worktreesBaseURL = parentURL.appendingPathComponent("worktrees")
        let namespaceDirectory = namespacedWorktreesDirectory(for: missingProjectURL, base: worktreesBaseURL)

        try FileManager.default.createDirectory(at: namespaceDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parentURL) }

        let shell = MockShellRunner()
        var settings = AppSettings()
        settings.worktreesBaseDirectory = worktreesBaseURL.path
        let manager = DefaultWorktreeManager(
            settingsService: InMemorySettingsService(current: settings),
            shell: shell
        )

        try await manager.removeAll(projectPath: missingProjectURL.path)

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingProjectURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: namespaceDirectory.path))
    }

    private func makeTemporaryProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeTemporaryWorktreesBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("worktrees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeProjectConfig(at projectURL: URL, json: String) throws {
        try json.write(to: projectURL.appendingPathComponent(".alveary.json"), atomically: true, encoding: .utf8)
    }

    private func worktreeListOutput(projectPath: String, worktreePath: String, branch: String) -> String {
        """
        worktree \(projectPath)
        HEAD abc123
        branch refs/heads/main

        worktree \(worktreePath)
        HEAD def456
        branch refs/heads/\(branch)
        """
    }

    private static func emptyShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
    }

    private static func failingShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 1, stdoutWasTruncated: false, stderrWasTruncated: false)
    }

    private func assertSetupInvocations(_ invocations: [MockShellRunner.Invocation], branch: String, worktreePath: String) {
        XCTAssertEqual(invocations[0].args, ["show-ref", "--verify", "--quiet", "refs/heads/af/fix-auth-bug-59c"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/heads/af/fix-auth-bug-59c-2"])
        XCTAssertEqual(invocations[2].args, ["fetch", "origin", "main"])
        XCTAssertEqual(invocations[3].args, ["worktree", "add", "--no-track", "-b", branch, worktreePath, "origin/main"])
        XCTAssertEqual(invocations[4].executable, "/bin/sh")
        XCTAssertEqual(invocations[4].timeout, Duration.seconds(45))
    }

    private func assertLifecycleEnvironment(
        _ environment: [String: String]?,
        threadName: String,
        branch: String,
        projectPath: String,
        worktreePath: String
    ) {
        XCTAssertEqual(environment?["ALVEARY_THREAD_NAME"], threadName)
        XCTAssertEqual(environment?["ALVEARY_BRANCH_NAME"], branch)
        XCTAssertEqual(environment?["ALVEARY_PROJECT_PATH"], projectPath)
        XCTAssertEqual(environment?["ALVEARY_WORKTREE_PATH"], worktreePath)
        XCTAssertEqual(environment?["ALVEARY_PORT_SEED"], shortHash(branch))
    }

    private func namespacedWorktreesDirectory(for projectURL: URL, base: URL) -> URL {
        let canonicalProjectPath = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        let projectName = URL(fileURLWithPath: canonicalProjectPath).lastPathComponent
        let digest = SHA256.hash(data: Data(canonicalProjectPath.utf8))
        let hash = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        let namespace = "\(slugify(projectName))-\(hash)"

        return base.appendingPathComponent(namespace)
    }

    private func slugify(_ value: String) -> String {
        let slug = value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !slug.isEmpty else {
            return "thread"
        }
        return String(slug.prefix(50))
    }

    private func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return String(hexDigest.prefix(3))
    }
}
