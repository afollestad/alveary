import Foundation
import XCTest

@testable import Alveary

@MainActor
final class GitHubAttachmentUploadServiceTests: XCTestCase {
    func testUploadUsesNativeAPIAndReturnsReferencesInOrder() async throws {
        let shell = MockShellRunner()
        await enqueuePreflight(shell)
        await enqueueAsset(shell, id: Self.firstAssetID)
        await enqueueAsset(shell, id: Self.secondAssetID)
        let image = try file(named: "-[screen] #&+.PNG")
        let video = try file(named: "demo.mov")

        let batch = try await makeService(shell).upload(files: [image, video], repository: "owner/repo")

        XCTAssertNil(batch.failure)
        XCTAssertEqual(batch.uploads.map(\.fileURL), [image, video])
        XCTAssertEqual(batch.uploads[0].markdownReference, "![-\\[screen\\] #&+.PNG](\(Self.assetURL(Self.firstAssetID)))")
        XCTAssertEqual(batch.uploads[1].markdownReference, Self.assetURL(Self.secondAssetID))
        let calls = await shell.invocations
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls[1].args, ["api", "--hostname", "github.com", "repos/owner/repo"])
        XCTAssertEqual(calls[2].args, [
            "api", "--hostname", "github.com", "--method", "POST",
            "https://uploads.github.com/user-attachments/assets", "--input", image.path,
            "--header", "Content-Type: application/octet-stream", "--header", "Accept: application/vnd.github+json",
            "--raw-field", "name=-[screen] #&+.PNG", "--raw-field", "content_type=image/png", "--field", "repository_id=42"
        ])
        XCTAssertTrue(calls[3].args.contains("content_type=video/quicktime"))
        for call in calls {
            XCTAssertEqual(call.executable, "/opt/homebrew/bin/gh")
            XCTAssertEqual(call.standardInput, .nullDevice)
            XCTAssertEqual(call.stdoutLimitBytes, 64 * 1024)
            XCTAssertEqual(call.stderrLimitBytes, 64 * 1024)
        }
        XCTAssertEqual(calls[0].timeout, .seconds(20))
        XCTAssertEqual(calls[2].timeout, .seconds(300))
    }

    func testPartialFailureRetainsUploadsAndDoesNotAttemptRemainingFiles() async throws {
        let shell = MockShellRunner()
        await enqueuePreflight(shell)
        await enqueueAsset(shell)
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "gh: unavailable (HTTP 503)", exitCode: 1)))
        let files = try [file(named: "a.png"), file(named: "b.png"), file(named: "c.png")]

        let batch = try await makeService(shell).upload(files: files, repository: "owner/repo")

        XCTAssertEqual(batch.uploads.map(\.fileURL), [files[0]])
        XCTAssertEqual(batch.failure, .uploadFailed("gh: unavailable (HTTP 503)"))
        let calls = await shell.invocations
        XCTAssertEqual(calls.count, 4)
    }

    func testCancellationAfterConfirmedUploadRetainsItsReference() async throws {
        let shell = CancellingAttachmentShellRunner()
        let service = makeService(shell)
        let files = try [file(named: "a.png"), file(named: "b.png")]
        let task = Task { try await service.upload(files: files, repository: "owner/repo") }

        let batch = try await task.value

        XCTAssertEqual(batch.uploads.map(\.fileURL), [files[0]])
        XCTAssertEqual(batch.failure, .cancelled)
        let calls = await shell.callCount
        XCTAssertEqual(calls, 3)
    }

    func testPreflightRejectsWholeBatchBeforeInvokingGh() async throws {
        let shell = MockShellRunner()
        let files = try [file(named: "ok.png"), file(named: "report.pdf")]
        do {
            _ = try await makeService(shell).upload(files: files, repository: "owner/repo")
            XCTFail("Expected unsupported file")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .unsupportedFile("report.pdf"))
        }
        let calls = await shell.invocations
        XCTAssertTrue(calls.isEmpty)
    }

    func testAllSupportedFormatsAndInclusiveLimits() throws {
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "svg", "mp4", "mov", "webm"] {
            let isVideo = ["mp4", "mov", "webm"].contains(ext)
            let limit = (isVideo ? 100 : 10) * 1024 * 1024
            let url = try file(named: "boundary.\(ext)", size: limit)
            XCTAssertNoThrow(try GitHubAttachmentFile(url))
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(limit + 1))
            try handle.close()
            XCTAssertThrowsError(try GitHubAttachmentFile(url)) { error in
                guard case .fileTooLarge = error as? GitHubAttachmentUploadError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testInvalidFilesAreRejectedWithoutOpeningPipes() throws {
        let empty = try file(named: "empty.png", size: 0)
        let missing = empty.deletingLastPathComponent().appendingPathComponent("missing.png")
        let directory = empty.deletingLastPathComponent()
        let fifo = directory.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        for url in [empty, missing, directory, fifo, URL(string: "https://example.com/a.png")!] {
            XCTAssertThrowsError(try GitHubAttachmentFile(url)) { error in
                guard case .invalidFile = error as? GitHubAttachmentUploadError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testEmptyBatchAndMissingCLI() async throws {
        let shell = MockShellRunner()
        let service = makeService(shell, path: nil)
        let batch = try await service.upload(files: [], repository: "owner/repo")
        XCTAssertEqual(batch, GitHubAttachmentUploadBatch(uploads: []))
        do {
            _ = try await service.upload(files: [file(named: "a.png")], repository: "owner/repo")
            XCTFail("Expected missing CLI")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .ghNotInstalled)
        }
        let calls = await shell.invocations
        XCTAssertTrue(calls.isEmpty)
    }

    func testReferenceURLAndMarkdownEscaping() throws {
        let url = URL(string: Self.assetURL(Self.firstAssetID))!
        let attachment = try GitHubAttachmentFile(file(named: "a\\[b]\n.png"))
        let upload = attachment.upload(at: url)
        XCTAssertEqual(upload.markdownReference, "![a\\\\\\[b\\] .png](\(url.absoluteString))")
        XCTAssertEqual(upload.referenceURL, url)
        let video = try GitHubAttachmentFile(file(named: "a.mp4")).upload(at: url)
        XCTAssertEqual(video.referenceURL, url)
    }
}
