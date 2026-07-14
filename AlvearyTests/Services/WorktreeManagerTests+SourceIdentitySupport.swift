import Foundation
import XCTest

@testable import Alveary

actor BranchRefRaceShell: ShellRunner {
    enum Mode: Sendable, Equatable {
        case directMatching
        case directRetarget
        case failedDeleteRefUnchanged
        case failedDeleteRefAbsent
        case failedDeleteLookupThrows
        case failedDeleteLookupInvalidExit
        case failedDeleteLookupEmptyOID
        case removeRetarget
        case rollbackRetarget
    }

    private let mode: Mode
    private let projectPath: String?
    private let initialWorktreePath: String?
    private var currentBranchOID = WorktreeTestObjectID.owned
    private var currentWorktreePath: String?
    private var currentBranch = "alveary/owned"
    private var recordedInvocations: [MockShellRunner.Invocation] = []

    init(
        mode: Mode,
        projectPath: String? = nil,
        worktreePath: String? = nil
    ) {
        self.mode = mode
        self.projectPath = projectPath
        self.initialWorktreePath = worktreePath
        self.currentWorktreePath = worktreePath
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        recordedInvocations.append(.init(
            executable: executable,
            args: args,
            directory: directory,
            environment: options.environment,
            timeout: options.timeout,
            stdoutLimitBytes: options.stdoutLimitBytes,
            stderrLimitBytes: options.stderrLimitBytes,
            standardInput: options.standardInput
        ))

        if args.starts(with: ["show-ref", "--verify", "--quiet"]) {
            return result(exitCode: 1)
        }
        if args.starts(with: ["worktree", "add"]) {
            currentBranch = args[4]
            currentWorktreePath = args[5]
            currentBranchOID = WorktreeTestObjectID.owned
            try FileManager.default.createDirectory(atPath: args[5], withIntermediateDirectories: true)
            return result()
        }
        if args == ["worktree", "list", "--porcelain"] {
            return result(stdout: worktreeListOutput())
        }
        if executable == "/bin/sh" {
            return result(stderr: "setup failed", exitCode: 1)
        }
        if args.starts(with: ["worktree", "remove"]) {
            if mode == .removeRetarget || mode == .rollbackRetarget {
                currentBranchOID = WorktreeTestObjectID.replacement
            }
            return result()
        }
        if let result = updateRefResult(for: args) {
            return result
        }
        if let result = try showRefResult(for: args) {
            return result
        }
        return result()
    }

    func branchOID() -> String? {
        currentBranchOID.isEmpty ? nil : currentBranchOID
    }

    func invocations() -> [MockShellRunner.Invocation] {
        recordedInvocations
    }

    private func updateRefResult(for args: [String]) -> ShellResult? {
        guard args.starts(with: ["update-ref", "-d"]) else {
            return nil
        }
        switch mode {
        case .directRetarget:
            currentBranchOID = WorktreeTestObjectID.replacement
        case .failedDeleteRefAbsent:
            currentBranchOID = ""
            return result(stderr: "delete failed", exitCode: 1)
        case .failedDeleteRefUnchanged,
             .failedDeleteLookupThrows,
             .failedDeleteLookupInvalidExit,
             .failedDeleteLookupEmptyOID:
            return result(stderr: "delete failed", exitCode: 1)
        default:
            break
        }
        guard currentBranchOID == args[4] else {
            return result(stderr: "ref changed", exitCode: 1)
        }
        currentBranchOID = ""
        return result()
    }

    private func showRefResult(for args: [String]) throws -> ShellResult? {
        guard args.starts(with: ["show-ref", "--hash", "--verify"]) else {
            return nil
        }
        switch mode {
        case .failedDeleteLookupThrows:
            throw BranchRefRaceShellError.lookupFailed
        case .failedDeleteLookupInvalidExit:
            return result(stderr: "lookup failed", exitCode: 128)
        case .failedDeleteLookupEmptyOID:
            return result()
        default:
            return currentBranchOID.isEmpty
                ? result(exitCode: 1)
                : result(stdout: "\(currentBranchOID)\n")
        }
    }

    private func worktreeListOutput() -> String {
        let worktreePath = currentWorktreePath ?? initialWorktreePath ?? "/tmp/worktree"
        let mainWorktree = projectPath.map {
            "worktree \($0)\nHEAD \(WorktreeTestObjectID.main)\nbranch refs/heads/main\n\n"
        } ?? ""
        return mainWorktree +
            "worktree \(worktreePath)\nHEAD \(currentBranchOID)\nbranch refs/heads/\(currentBranch)\n\n"
    }

    private func result(
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0
    ) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}

enum BranchRefRaceShellError: Error, Equatable {
    case lookupFailed
}

enum BranchDeletionExpectedOutcome {
    case success
    case retryableGit(GitError)
    case shellFailure(BranchRefRaceShellError)
    case gitFailure(GitError)
}

@MainActor
extension WorktreeManagerTests {
    func assertAtomicBranchDeletion(
        _ mode: BranchRefRaceShell.Mode,
        expected outcome: BranchDeletionExpectedOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let shell = BranchRefRaceShell(mode: mode)
        let manager = DefaultWorktreeManager(settingsService: InMemorySettingsService(), shell: shell)
        let caughtError: Error?
        do {
            try await manager.deleteBranch(
                projectPath: "/tmp/project",
                branch: "alveary/owned",
                expectedOID: WorktreeTestObjectID.owned
            )
            caughtError = nil
        } catch {
            caughtError = error
        }

        switch outcome {
        case .success:
            XCTAssertNil(caughtError, file: file, line: line)
        case .retryableGit(let expected):
            let retryable = caughtError as? RetryableWorktreeBranchDeletionError
            XCTAssertNotNil(retryable, file: file, line: line)
            XCTAssertEqual(retryable?.underlying as? GitError, expected, file: file, line: line)
        case .shellFailure(let expected):
            XCTAssertFalse(caughtError is RetryableWorktreeBranchDeletionError, file: file, line: line)
            XCTAssertEqual(caughtError as? BranchRefRaceShellError, expected, file: file, line: line)
        case .gitFailure(let expected):
            XCTAssertFalse(caughtError is RetryableWorktreeBranchDeletionError, file: file, line: line)
            XCTAssertEqual(caughtError as? GitError, expected, file: file, line: line)
        }

        let invocations = await shell.invocations()
        let branchInvocations = Array(invocations.map(\.args).prefix(2))
        XCTAssertEqual(branchInvocations, Self.expectedBranchDeleteInvocations, file: file, line: line)
    }

    private static let expectedBranchDeleteInvocations = [
        ["update-ref", "-d", "--", "refs/heads/alveary/owned", WorktreeTestObjectID.owned],
        ["show-ref", "--hash", "--verify", "refs/heads/alveary/owned"]
    ]
}
