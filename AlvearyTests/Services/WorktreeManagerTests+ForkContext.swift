import Foundation
import XCTest

@testable import Alveary

extension WorktreeManagerTests {
    func testPrepareForkContextAppliesTrackedDiffPatch() async throws {
        let sourceURL = try makeTemporaryProject()
        let worktreeURL = try makeTemporaryProject()
        let shell = MockShellRunner()
        await shell.enqueue(.success(ShellResult(
            stdout: "diff --git a/file.txt b/file.txt\n",
            stderr: "",
            exitCode: 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )))
        await shell.enqueue(.success(Self.emptyShellResult()))
        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.prepareForkContext(sourcePath: sourceURL.path, worktreePath: worktreeURL.path)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].args, ["diff", "--binary", "HEAD", "--"])
        XCTAssertEqual(invocations[0].directory, sourceURL.path)
        XCTAssertEqual(Array(invocations[1].args.prefix(2)), ["apply", "--whitespace=nowarn"])
        XCTAssertEqual(invocations[1].directory, worktreeURL.path)
    }

    func testPrepareForkContextCopiesIgnoredWorktreeIncludeMatchesWithoutOverwriting() async throws {
        let sourceURL = try makeTemporaryProject()
        let worktreeURL = try makeTemporaryProject()
        try "secret.env\ncache\n".write(to: sourceURL.appendingPathComponent(".worktreeinclude"), atomically: true, encoding: .utf8)
        try "source secret".write(to: sourceURL.appendingPathComponent("secret.env"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try "cached".write(to: sourceURL.appendingPathComponent("cache/log.txt"), atomically: true, encoding: .utf8)
        try "existing".write(to: worktreeURL.appendingPathComponent("secret.env"), atomically: true, encoding: .utf8)
        let shell = MockShellRunner()
        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)

        try await manager.prepareForkContext(sourcePath: sourceURL.path, worktreePath: worktreeURL.path)

        let existingSecret = try String(contentsOf: worktreeURL.appendingPathComponent("secret.env"), encoding: .utf8)
        let copiedCache = try String(contentsOf: worktreeURL.appendingPathComponent("cache/log.txt"), encoding: .utf8)
        let invocations = await shell.invocations

        XCTAssertEqual(existingSecret, "existing")
        XCTAssertEqual(copiedCache, "cached")
        XCTAssertEqual(invocations.first?.args, ["diff", "--binary", "HEAD", "--"])
    }
}
