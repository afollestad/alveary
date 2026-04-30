import Foundation
import XCTest

@testable import Alveary

extension GitServiceTests {
    func testImageBlobLoadsBinaryGitObjectData() async throws {
        let shell = MockShellRunner()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        await shell.enqueue(
            .success(
                ShellResult(
                    stdout: "",
                    stdoutData: bytes,
                    stderr: "",
                    exitCode: 0,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            )
        )

        let service = CLIGitService(shell: shell)

        let data = try await service.imageBlob(
            source: .commit(hash: "abc123", path: "Assets/logo.png"),
            maxBytes: 20,
            in: "/tmp/project"
        )

        XCTAssertEqual(data, bytes)
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, ["show", "abc123:Assets/logo.png"])
        XCTAssertEqual(invocation.stdoutLimitBytes, 20)
    }

    func testImageBlobUsesIndexSpecForStagedImage() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdoutData: Data([1, 2, 3]))))

        let service = CLIGitService(shell: shell)

        _ = try await service.imageBlob(source: .index(path: "Assets/logo.png"), maxBytes: 20, in: "/tmp/project")

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.args, ["show", ":Assets/logo.png"])
    }

    func testImageBlobThrowsWhenGitBlobIsTruncated() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(Self.shellResult(stdoutData: Data([1, 2, 3]), stdoutWasTruncated: true)))

        let service = CLIGitService(shell: shell)

        do {
            _ = try await service.imageBlob(source: .head(path: "Assets/logo.png"), maxBytes: 2, in: "/tmp/project")
            XCTFail("Expected imageBlob to throw")
        } catch GitError.outputTooLarge(let message) {
            XCTAssertEqual(message, "Image blob exceeded 0MB")
        }
    }

    func testImageBlobRejectsOversizedWorktreeFileBeforeReading() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let imageURL = tempDirectory.appendingPathComponent("large.png")
        try Data(repeating: 0, count: 4).write(to: imageURL)
        let service = CLIGitService(shell: MockShellRunner())

        do {
            _ = try await service.imageBlob(source: .worktree(path: "large.png"), maxBytes: 3, in: tempDirectory.path)
            XCTFail("Expected imageBlob to throw")
        } catch GitError.outputTooLarge(let message) {
            XCTAssertEqual(message, "Image file exceeded 0MB")
        }
    }

    func testImageBlobLoadsWorktreeFileAtExactByteLimit() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let imageURL = tempDirectory.appendingPathComponent("exact.png")
        try bytes.write(to: imageURL)
        let service = CLIGitService(shell: MockShellRunner())

        let data = try await service.imageBlob(source: .worktree(path: "exact.png"), maxBytes: bytes.count, in: tempDirectory.path)

        XCTAssertEqual(data, bytes)
    }
}
