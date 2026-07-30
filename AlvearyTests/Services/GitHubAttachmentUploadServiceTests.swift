import Foundation
import XCTest

@testable import Alveary

@MainActor
final class GitHubAttachmentUploadServiceTests: XCTestCase {
    private func makeService(shell: MockShellRunner, path: String? = "/opt/homebrew/bin/gh") -> DefaultGitHubAttachmentUploadService {
        DefaultGitHubAttachmentUploadService(
            shellRunner: shell,
            executableResolver: PullRequestsExecutablePathResolverFake(path: path)
        )
    }

    func testUploadReturnsOneReferencePerFileInOrder() async throws {
        let shell = MockShellRunner()
        let stdout = """
        ![a.png](https://github.com/user-attachments/assets/aaa)
        ![b.png](https://github.com/user-attachments/assets/bbb)
        """
        await shell.enqueue(.success(pullRequestsShellResult(stdout: stdout)))
        let service = makeService(shell: shell)
        let files = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]

        let uploads = try await service.upload(files: files, repository: "afollestad/af.codes")

        XCTAssertEqual(uploads.map(\.fileURL), files)
        XCTAssertEqual(
            uploads.map(\.markdownReference),
            [
                "![a.png](https://github.com/user-attachments/assets/aaa)",
                "![b.png](https://github.com/user-attachments/assets/bbb)"
            ]
        )
    }

    func testUploadInvokesGhImageWithRepoAndFileSeparator() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "![a.png](https://example.com/a)")))
        let service = makeService(shell: shell)

        _ = try await service.upload(files: [URL(fileURLWithPath: "/tmp/a.png")], repository: "owner/repo")

        let invocation = await shell.invocations.first
        XCTAssertEqual(invocation?.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(invocation?.args, ["image", "--repo", "owner/repo", "--", "/tmp/a.png"])
        // Never inherit stdin: a prompt would otherwise hang the upload.
        XCTAssertEqual(invocation?.standardInput, .nullDevice)
    }

    func testUploadThrowsWhenReferenceCountDiffersFromFileCount() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "![only-one](https://example.com/a)")))
        let service = makeService(shell: shell)
        let files = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]

        do {
            _ = try await service.upload(files: files, repository: "owner/repo")
            XCTFail("Expected incompleteOutput")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .incompleteOutput)
        }
    }

    func testUploadMapsUnknownCommandToExtensionMissing() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stderr: "unknown command \"image\" for \"gh\"",
            exitCode: 1
        )))
        let service = makeService(shell: shell)

        do {
            _ = try await service.upload(files: [URL(fileURLWithPath: "/tmp/a.png")], repository: "owner/repo")
            XCTFail("Expected extensionMissing")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .extensionMissing)
        }
    }

    func testUploadMapsSessionFailureToSessionUnavailable() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stderr: "no user_session cookie found; please sign in",
            exitCode: 1
        )))
        let service = makeService(shell: shell)

        do {
            _ = try await service.upload(files: [URL(fileURLWithPath: "/tmp/a.png")], repository: "owner/repo")
            XCTFail("Expected sessionUnavailable")
        } catch {
            guard case .sessionUnavailable = error as? GitHubAttachmentUploadError else {
                return XCTFail("Expected sessionUnavailable, got \(error)")
            }
        }
    }

    func testUploadThrowsGhNotInstalledWhenPathUnresolved() async {
        let shell = MockShellRunner()
        let service = makeService(shell: shell, path: nil)

        do {
            _ = try await service.upload(files: [URL(fileURLWithPath: "/tmp/a.png")], repository: "owner/repo")
            XCTFail("Expected ghNotInstalled")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .ghNotInstalled)
        }
        let count = await shell.invocations.count
        XCTAssertEqual(count, 0)
    }

    func testEmptyFileListSkipsShellEntirely() async throws {
        let shell = MockShellRunner()
        let service = makeService(shell: shell)

        let uploads = try await service.upload(files: [], repository: "owner/repo")

        XCTAssertTrue(uploads.isEmpty)
        let count = await shell.invocations.count
        XCTAssertEqual(count, 0)
    }

    func testIsAvailableReflectsVersionExitCode() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "gh-image 1.0.0")))
        let service = makeService(shell: shell)

        let available = await service.isAvailable()
        XCTAssertTrue(available)
    }

    func testIsAvailableFalseWhenGhMissing() async {
        let service = makeService(shell: MockShellRunner(), path: nil)
        let available = await service.isAvailable()
        XCTAssertFalse(available)
    }

    /// Oversized files fail before the extension is invoked, with a message
    /// naming the file and GitHub's limit — not the endpoint's HTML-laden 422.
    func testUploadRejectsAnOversizedImageBeforeInvokingTheCLI() async throws {
        let shell = MockShellRunner()
        let service = makeService(shell: shell)
        let fileURL = try Self.writeTemporaryFile(named: "big.jpg", byteCount: (10 * 1024 * 1024) + 1)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await service.upload(files: [fileURL], repository: "owner/repo")
            XCTFail("Expected fileTooLarge")
        } catch let error as GitHubAttachmentUploadError {
            guard case .fileTooLarge(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("big.jpg"), message)
            XCTAssertTrue(message.contains("10 MB"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let count = await shell.invocations.count
        XCTAssertEqual(count, 0)
    }

    /// The image limit must not apply to other kinds — a 10 MB+ archive is
    /// fine because non-image files get 25 MB.
    func testUploadAllowsANonImageFileOverTheImageLimit() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "[big.zip](https://example.com/a)")))
        let service = makeService(shell: shell)
        let fileURL = try Self.writeTemporaryFile(named: "big.zip", byteCount: (10 * 1024 * 1024) + 1)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let uploads = try await service.upload(files: [fileURL], repository: "owner/repo")

        XCTAssertEqual(uploads.count, 1)
    }

    /// GitHub's enforced threshold can be stricter than the advertised limit;
    /// the policy endpoint's size 422 still maps to a readable message.
    func testServerSideSizeRejectionClassifiesAsFileTooLarge() async {
        let shell = MockShellRunner()
        let stderr = """
        Error uploading /tmp/a.png: step 1 (request policy): expected 201, got 422: \
        {"errors":[{"resource":"UserAsset","code":"custom","field":"size","message":"size Yowza that's a big file."}]}
        """
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "", stderr: stderr, exitCode: 1)))
        let service = makeService(shell: shell)

        do {
            _ = try await service.upload(files: [URL(fileURLWithPath: "/tmp/a.png")], repository: "owner/repo")
            XCTFail("Expected fileTooLarge")
        } catch let error as GitHubAttachmentUploadError {
            guard case .fileTooLarge(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertFalse(message.contains("Yowza"), message)
            XCTAssertTrue(message.contains("10 MB"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func writeTemporaryFile(named name: String, byteCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachment-size-\(UUID().uuidString)-\(name)")
        try Data(count: byteCount).write(to: url)
        return url
    }

    func testReferenceURLExtractsEveryReferenceFormTheExtensionPrints() {
        func upload(_ reference: String) -> GitHubAttachmentUpload {
            GitHubAttachmentUpload(fileURL: URL(fileURLWithPath: "/tmp/a.png"), markdownReference: reference)
        }

        XCTAssertEqual(
            upload("![a.png](https://github.com/user-attachments/assets/aaa)").referenceURL?.absoluteString,
            "https://github.com/user-attachments/assets/aaa"
        )
        XCTAssertEqual(
            upload("[report.pdf](https://github.com/user-attachments/files/1/report.pdf)").referenceURL?.absoluteString,
            "https://github.com/user-attachments/files/1/report.pdf"
        )
        // Videos come back as a bare URL.
        XCTAssertEqual(
            upload("https://github.com/user-attachments/assets/bbb").referenceURL?.absoluteString,
            "https://github.com/user-attachments/assets/bbb"
        )
        XCTAssertNil(upload("not a reference").referenceURL)
    }
}
