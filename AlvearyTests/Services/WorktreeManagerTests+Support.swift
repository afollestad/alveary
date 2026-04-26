import CryptoKit
import Foundation
import XCTest

@testable import Alveary

extension WorktreeManagerTests {
    func makeTemporaryProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func makeTemporaryWorktreesBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("worktrees-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func writeProjectConfig(at projectURL: URL, json: String) throws {
        try json.write(to: projectURL.appendingPathComponent(".alveary.json"), atomically: true, encoding: .utf8)
    }

    func worktreeListOutput(projectPath: String, worktreePath: String, branch: String) -> String {
        """
        worktree \(projectPath)
        HEAD abc123
        branch refs/heads/main

        worktree \(worktreePath)
        HEAD def456
        branch refs/heads/\(branch)
        """
    }

    static func emptyShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
    }

    static func failingShellResult() -> ShellResult {
        ShellResult(stdout: "", stderr: "", exitCode: 1, stdoutWasTruncated: false, stderrWasTruncated: false)
    }

    func assertSetupInvocations(_ invocations: [MockShellRunner.Invocation], branch: String, worktreePath: String) {
        XCTAssertEqual(invocations[0].args, ["show-ref", "--verify", "--quiet", "refs/heads/af-fix-auth-bug-59c"])
        XCTAssertEqual(invocations[1].args, ["show-ref", "--verify", "--quiet", "refs/heads/af-fix-auth-bug-59c-2"])
        XCTAssertEqual(invocations[2].args, ["fetch", "origin", "main"])
        XCTAssertEqual(invocations[3].args, ["worktree", "add", "--no-track", "-b", branch, worktreePath, "origin/main"])
        XCTAssertEqual(invocations[4].executable, "/bin/sh")
        XCTAssertEqual(invocations[4].timeout, Duration.seconds(45))
    }

    func assertLifecycleEnvironment(
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

    func namespacedWorktreesDirectory(for projectURL: URL, base: URL) -> URL {
        let canonicalProjectPath = projectURL.resolvingSymlinksInPath().standardizedFileURL.path
        let projectName = URL(fileURLWithPath: canonicalProjectPath).lastPathComponent
        let digest = SHA256.hash(data: Data(canonicalProjectPath.utf8))
        let hash = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        let namespace = "\(slugify(projectName))-\(hash)"

        return base.appendingPathComponent(namespace)
    }

    func slugify(_ value: String) -> String {
        let slug = value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !slug.isEmpty else {
            return "thread"
        }
        return String(slug.prefix(50))
    }

    func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return String(hexDigest.prefix(3))
    }
}
