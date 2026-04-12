import Foundation
import XCTest

@testable import Alveary

final class GitServiceTests: XCTestCase {
    func testStatusRequestsExpandedUntrackedFilePaths() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        _ = try await service.status(in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(
            invocations[0].args,
            ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--no-ahead-behind", "--untracked-files=all"]
        )
    }

    func testStatusParsesOrdinaryRenameUnmergedAndUntrackedEntries() async throws {
        let shell = MockShellRunner()
        let statusOutput = [
            "1 MM N... 100644 100644 100644 abc abc feature.swift",
            "2 R. N... 100644 100644 100644 abc abc R100 renamed.swift",
            "original.swift",
            "u UU N... 100644 100644 100644 100644 abc abc abc conflicted.swift",
            "? notes.txt"
        ].joined(separator: "\0") + "\0"
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: statusOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        let statuses = try await service.status(in: "/tmp/project")

        XCTAssertEqual(
            statuses,
            [
                FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: true),
                FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false),
                FileStatus(path: "renamed.swift", originalPath: "original.swift", status: .renamed, isStaged: true),
                FileStatus(path: "conflicted.swift", originalPath: nil, status: .unmerged, isStaged: false),
                FileStatus(path: "notes.txt", originalPath: nil, status: .untracked, isStaged: false)
            ]
        )
    }

    func testDiscardRestoresTrackedFilesAndDeletesUntrackedFiles() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let untrackedFile = tempDirectory.appendingPathComponent("notes.txt")
        try "temporary".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let shell = MockShellRunner()
        let statusOutput = [
            "1 .M N... 100644 100644 100644 abc abc tracked.swift",
            "? notes.txt"
        ].joined(separator: "\0") + "\0"
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: statusOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        try await service.discard(paths: ["tracked.swift", "notes.txt"], in: tempDirectory.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedFile.path))

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[1].args, ["restore", "--source=HEAD", "--staged", "--worktree", "--", "tracked.swift"])
    }

    func testSyntheticAddedDiffMarksBinaryFilesAsBinary() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let imagePath = "Snapshots/example.png"
        let imageURL = tempDirectory
            .appendingPathComponent("Snapshots", isDirectory: true)
            .appendingPathComponent("example.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        try pngHeader.write(to: imageURL)

        let service = CLIGitService(shell: MockShellRunner())

        let diff = try await service.syntheticAddedDiff(for: imagePath, in: tempDirectory.path)

        XCTAssertEqual(
            diff,
            """
            diff --git a/Snapshots/example.png b/Snapshots/example.png
            new file mode 100644
            Binary files /dev/null and b/Snapshots/example.png differ
            """
        )
        XCTAssertEqual(DiffParser.parse(diff).first?.isBinary, true)
        XCTAssertNil(DiffParser.parse(diff).first?.oldPath)
        XCTAssertEqual(DiffParser.parse(diff).first?.newPath, imagePath)
    }

    func testDiscardWorktreeOnlyRestoresTrackedFilesWithoutResettingIndex() async throws {
        let shell = MockShellRunner()
        let statusOutput = "1 .M N... 100644 100644 100644 abc abc tracked.swift\0"
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: statusOutput,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        try await service.discard(paths: ["tracked.swift"], scope: .worktreeOnly, in: "/tmp/project")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[1].args, ["restore", "--worktree", "--", "tracked.swift"])
    }

    func testCommitsAheadOfBasePrefersRemoteTrackedRefWhenItExists() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "3\n",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        let count = try await service.commitsAheadOfBase(baseBranch: "main", remoteName: "origin", in: "/tmp/project")

        XCTAssertEqual(count, 3)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].args, ["show-ref", "--verify", "--quiet", "refs/remotes/origin/main"])
        XCTAssertEqual(invocations[1].args, ["rev-list", "origin/main..HEAD", "--count"])
    }

    func testLogParsesSingleCommitWithEmptySubject() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "abc123\n\nAlice\n2024-01-01T12:34:56Z",
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        let commits = try await service.log(in: "/tmp/project", limit: 1)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.hash, "abc123")
        XCTAssertEqual(commits.first?.message, "")
        XCTAssertEqual(commits.first?.author, "Alice")
    }
}
