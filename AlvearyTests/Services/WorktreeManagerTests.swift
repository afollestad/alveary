import Foundation
import XCTest

@testable import Alveary

@MainActor
final class WorktreeManagerTests: XCTestCase {
    func testCreateUsesSetupScriptEnvironmentAndCollisionSuffix() async throws {
        let projectURL = try makeTemporaryProject()
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
        XCTAssertEqual(invocations[0].args, ["show-ref", "--verify", "--quiet", "refs/heads/af/fix-auth-bug-59c"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/heads/af/fix-auth-bug-59c-2"])
        XCTAssertEqual(invocations[2].args, ["fetch", "origin", "main"])
        XCTAssertEqual(invocations[3].args, ["worktree", "add", "--no-track", "-b", info.branch, info.path, "origin/main"])
        XCTAssertEqual(invocations[4].executable, "/bin/sh")
        XCTAssertEqual(invocations[4].timeout, .seconds(45))
        XCTAssertEqual(invocations[4].environment?["SKEP_BRANCH_NAME"], info.branch)
        XCTAssertEqual(invocations[4].environment?["SKEP_PROJECT_PATH"], projectURL.path)
        XCTAssertEqual(invocations[4].environment?["SKEP_WORKTREE_PATH"], info.path)
    }

    func testCreateRollsBackWorktreeAndBranchWhenSetupFails() async throws {
        let projectURL = try makeTemporaryProject()
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

        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

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

    private func makeTemporaryProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeProjectConfig(at projectURL: URL, json: String) throws {
        try json.write(to: projectURL.appendingPathComponent(".alveary.json"), atomically: true, encoding: .utf8)
    }

    private static func emptyShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
    }

    private static func failingShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 1, stdoutWasTruncated: false, stderrWasTruncated: false)
    }
}
