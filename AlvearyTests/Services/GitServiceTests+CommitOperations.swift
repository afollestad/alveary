import Foundation
import XCTest

@testable import Alveary

extension GitServiceTests {
    func testHasStagedChangesReturnsTrueWhenCachedDiffExists() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(exitCode: 1)))
        let service = CLIGitService(shell: shell)

        let hasChanges = try await service.hasStagedChanges(in: "/tmp/project")

        XCTAssertTrue(hasChanges)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.first?.args, ["diff", "--cached", "--quiet", "--exit-code"])
    }

    func testHasStagedChangesReturnsFalseWhenCachedDiffIsEmpty() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        let hasChanges = try await service.hasStagedChanges(in: "/tmp/project")

        XCTAssertFalse(hasChanges)
    }

    func testValidateBranchNameUsesGitRefFormat() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "feature/test\n")))
        await shell.enqueue(.success(Self.shellResult(stderr: "fatal: invalid", exitCode: 128)))
        let service = CLIGitService(shell: shell)

        let valid = try await service.validateBranchName("feature/test", in: "/tmp/project")
        let invalid = try await service.validateBranchName("bad..name", in: "/tmp/project")

        XCTAssertTrue(valid)
        XCTAssertFalse(invalid)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["check-ref-format", "--branch", "feature/test"])
        XCTAssertEqual(invocations[1].args, ["check-ref-format", "--branch", "bad..name"])
    }

    func testValidateBranchNameRejectsBlankNameWithoutShellingOut() async throws {
        let shell = MockShellRunner()
        let service = CLIGitService(shell: shell)

        let valid = try await service.validateBranchName("  \n  ", in: "/tmp/project")
        let invocations = await shell.invocations

        XCTAssertFalse(valid)
        XCTAssertTrue(invocations.isEmpty)
    }

    func testCheckoutNewBranchUsesTrimmedBranchName() async throws {
        let shell = MockShellRunner()
        let service = CLIGitService(shell: shell)

        try await service.checkoutNewBranch(" feature/test\n", in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.first?.args, ["checkout", "-b", "feature/test"])
    }

    func testCommitWithoutUnstagedChangesCommitsExistingIndex() async throws {
        let shell = MockShellRunner()
        let service = CLIGitService(shell: shell)

        try await service.commit(message: "Commit subject", includeUnstagedChanges: false, in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(Array(invocations[0].args.prefix(3)), ["commit", "--cleanup=verbatim", "--file"])
        let messageFile = try XCTUnwrap(invocations[0].args.last)
        XCTAssertFalse(FileManager.default.fileExists(atPath: messageFile))
    }

    func testCommitWithUnstagedChangesStagesAllBeforeCommit() async throws {
        let shell = MockShellRunner()
        let service = CLIGitService(shell: shell)

        try await service.commit(message: "Commit subject", includeUnstagedChanges: true, in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].args, ["add", "--all"])
        XCTAssertEqual(Array(invocations[1].args.prefix(3)), ["commit", "--cleanup=verbatim", "--file"])
    }

    func testCommitUsesTempFileToPreserveMultilineMessageAndTrailer() async throws {
        let shell = CommitMessageCapturingShellRunner()
        let service = CLIGitService(shell: shell)
        let message = """
        Add commit modal

        Preserve message body text.

        Co-authored-by: Codex <noreply@openai.com>
        """

        try await service.commit(message: message, includeUnstagedChanges: false, in: "/tmp/project")

        let capturedMessage = await shell.capturedMessage
        XCTAssertEqual(capturedMessage, message)
        let invocations = await shell.invocations
        XCTAssertEqual(Array(invocations[0].args.prefix(3)), ["commit", "--cleanup=verbatim", "--file"])
    }

    func testPushCurrentBranchUsesRemoteAndCurrentBranch() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "feature/test\n")))
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        try await service.pushCurrentBranch(remoteName: "upstream", in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["rev-parse", "--abbrev-ref", "HEAD"])
        XCTAssertEqual(invocations[1].args, ["push", "-u", "upstream", "feature/test"])
    }

    func testPushCurrentBranchDefaultsToOriginWhenRemoteNameIsMissing() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdout: "feature/test\n")))
        await shell.enqueue(.success(Self.shellResult()))
        let service = CLIGitService(shell: shell)

        try await service.pushCurrentBranch(remoteName: nil, in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].args, ["push", "-u", "origin", "feature/test"])
    }
}

private actor CommitMessageCapturingShellRunner: ShellRunner {
    private(set) var invocations: [MockShellRunner.Invocation] = []
    private(set) var capturedMessage: String?

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        invocations.append(
            MockShellRunner.Invocation(
                executable: executable,
                args: args,
                directory: directory,
                environment: options.environment,
                timeout: options.timeout,
                stdoutLimitBytes: options.stdoutLimitBytes,
                stderrLimitBytes: options.stderrLimitBytes
            )
        )
        if let fileIndex = args.firstIndex(of: "--file"),
           args.indices.contains(fileIndex + 1) {
            capturedMessage = try String(contentsOfFile: args[fileIndex + 1], encoding: .utf8)
        }
        return GitServiceTests.shellResult()
    }
}
