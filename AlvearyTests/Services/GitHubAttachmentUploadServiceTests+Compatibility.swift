import Foundation
import XCTest

@testable import Alveary

@MainActor
extension GitHubAttachmentUploadServiceTests {
    func testSupportedVersionsProceedToUpload() async throws {
        let image = try file()
        for version in ["2.99.0", "2.99.1", "2.100.0", "3.0.0", "2.99.0-2-gabc123", "2.99.0+build.7"] {
            let shell = MockShellRunner()
            await enqueuePreflight(shell, version: version)
            await enqueueAsset(shell)
            let batch = try await makeService(shell).upload(files: [image], repository: "owner/repo")
            XCTAssertEqual(batch.uploads.count, 1, version)
            XCTAssertNil(batch.failure, version)
        }
    }

    func testOldVersionsStopBeforeRepositoryLookupOrUpload() async throws {
        let image = try file()
        for version in ["1.99.0", "2.9.0", "2.98.9"] {
            let shell = MockShellRunner()
            await enqueuePreflight(shell, version: version)
            do {
                _ = try await makeService(shell).upload(files: [image], repository: "owner/repo")
                XCTFail("Expected unsupported CLI")
            } catch {
                XCTAssertEqual(error as? GitHubAttachmentUploadError, .unsupportedCLI("\(version) at /opt/homebrew/bin/gh"))
                XCTAssertTrue(error.localizedDescription.contains("2.99.0"))
                XCTAssertTrue(error.localizedDescription.contains("brew upgrade gh"))
                XCTAssertTrue(error.localizedDescription.contains("https://cli.github.com/"))
            }
            let calls = await shell.invocations
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testMalformedFailedAndTruncatedProbesReportCompatibilityFailure() async throws {
        let image = try file()
        let responses: [MockShellRunner.Response] = [
            .success(pullRequestsShellResult(stdout: "wrapper version 9.0.0")),
            .success(pullRequestsShellResult(stdout: "gh version 2.99")),
            .success(pullRequestsShellResult(stdout: "gh version 2.99.0garbage")),
            .success(pullRequestsShellResult(stderr: "Cannot execute", exitCode: 1)),
            .success(ShellResult(stdout: "gh version 2.99.0", stderr: "", exitCode: 0, stdoutWasTruncated: true, stderrWasTruncated: false)),
            .failure(.message("probe failed"))
        ]
        for response in responses {
            let shell = MockShellRunner()
            await shell.enqueue(response)
            do {
                _ = try await makeService(shell).upload(files: [image], repository: "owner/repo")
                XCTFail("Expected compatibility failure")
            } catch {
                guard case .compatibilityCheckFailed = error as? GitHubAttachmentUploadError else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertTrue(error.localizedDescription.contains("/opt/homebrew/bin/gh"))
            }
            let calls = await shell.invocations
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testUpgradeIsDetectedByTheSameServiceOnNextBatch() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "gh version 2.98.0")))
        let service = makeService(shell)
        let image = try file()
        do {
            _ = try await service.upload(files: [image], repository: "owner/repo")
            XCTFail("Expected unsupported CLI")
        } catch {
            XCTAssertTrue(error is GitHubAttachmentUploadError)
        }
        await enqueuePreflight(shell)
        await enqueueAsset(shell)
        let batch = try await service.upload(files: [image], repository: "owner/repo")
        XCTAssertEqual(batch.uploads.count, 1)
        let calls = await shell.invocations
        XCTAssertEqual(calls.filter { $0.args == ["--version"] }.count, 2)
    }
}
