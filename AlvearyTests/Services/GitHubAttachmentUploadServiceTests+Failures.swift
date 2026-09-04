import Foundation
import XCTest

@testable import Alveary

@MainActor
extension GitHubAttachmentUploadServiceTests {
    func testRepositoryPermissionDenialNeverUploads() async throws {
        let shell = MockShellRunner()
        await enqueuePreflight(shell, push: false)
        do {
            _ = try await makeService(shell).upload(files: [file()], repository: "owner/repo")
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? GitHubAttachmentUploadError, .permissionDenied)
        }
        let calls = await shell.invocations
        XCTAssertEqual(calls.count, 2)
    }

    func testCLIAndHTTPFailuresAreDistinctAndNeverRetried() async throws {
        let image = try file()
        let cases: [(String, GitHubAttachmentUploadError)] = [
            ("unknown command api", .unsupportedFunctionality("unknown command api")),
            ("unknown flag: --input", .unsupportedFunctionality("unknown flag: --input")),
            ("unknown shorthand flag: 'H'", .unsupportedFunctionality("unknown shorthand flag: 'H'")),
            ("gh: Bad credentials (HTTP 401)", .notAuthenticated),
            ("please run gh auth login", .notAuthenticated),
            ("gh: Forbidden (HTTP 403)", .permissionDenied),
            ("gh: Not Found (HTTP 404)", .repositoryUnavailable),
            ("gh: Rate limit (HTTP 429)", .rateLimited("gh: Rate limit (HTTP 429)")),
            ("gh: rate limit exceeded (HTTP 403)", .rateLimited("gh: rate limit exceeded (HTTP 403)")),
            ("gh: Server error (HTTP 500)", .uploadFailed("gh: Server error (HTTP 500)"))
        ]
        for (message, expected) in cases {
            let shell = MockShellRunner()
            await enqueuePreflight(shell)
            await shell.enqueue(.success(pullRequestsShellResult(stderr: message, exitCode: 1)))
            let batch = try await makeService(shell).upload(files: [image], repository: "owner/repo")
            XCTAssertTrue(batch.uploads.isEmpty)
            XCTAssertEqual(batch.failure, expected)
            let calls = await shell.invocations
            XCTAssertEqual(calls.count, 3)
        }
    }

    func testServerSizeAndTransportFailures() async throws {
        let image = try file()
        let shell = MockShellRunner()
        await enqueuePreflight(shell)
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: #"{"message":"Validation Failed","errors":[{"resource":"UserAsset","field":"size"}]}"#,
            stderr: "gh: Validation Failed (HTTP 422)", exitCode: 1
        )))
        let batch = try await makeService(shell).upload(files: [image], repository: "owner/repo")
        guard case .fileTooLarge = batch.failure else {
            return XCTFail("Expected file size error")
        }
        await enqueuePreflight(shell)
        await shell.enqueue(.failure(.message("network failed")))
        let transportBatch = try await makeService(shell).upload(files: [image], repository: "owner/repo")
        guard case .uploadFailed = transportBatch.failure else {
            return XCTFail("Expected transport failure")
        }
    }

    func testMalformedAndTruncatedUploadResponsesKeepEarlierSuccess() async throws {
        let files = try [file(named: "a.png"), file(named: "b.png")]
        let invalidBodies = [
            "not JSON", #"{"url":""}"#, "{}",
            #"{"url":"https://example.com/user-attachments/assets/11111111-1111-1111-1111-111111111111"}"#,
            #"{"url":"http://github.com/user-attachments/assets/11111111-1111-1111-1111-111111111111"}"#,
            #"{"url":"https://github.com/user-attachments/assets/invalid)"}"#
        ]
        var responses = invalidBodies.map { pullRequestsShellResult(stdout: $0) }
        responses.append(ShellResult(
            stdout: "{}", stderr: "", exitCode: 0, stdoutWasTruncated: true, stderrWasTruncated: false
        ))
        for response in responses {
            let shell = MockShellRunner()
            await enqueuePreflight(shell)
            await enqueueAsset(shell)
            await shell.enqueue(.success(response))
            let batch = try await makeService(shell).upload(files: files, repository: "owner/repo")
            XCTAssertEqual(batch.uploads.map(\.fileURL), [files[0]])
            guard case .invalidResponse = batch.failure else {
                return XCTFail("Expected invalid response: \(String(describing: batch.failure))")
            }
        }
    }

    func testInvalidRepositoryResponsesPreventUpload() async throws {
        let image = try file()
        let bodies = ["{}", #"{"id":0,"permissions":{"push":true}}"#, #"{"id":42}"#, "not JSON"]
        for body in bodies {
            let shell = MockShellRunner()
            await shell.enqueue(.success(pullRequestsShellResult(stdout: "gh version 2.99.0")))
            await shell.enqueue(.success(pullRequestsShellResult(stdout: body)))
            do {
                _ = try await makeService(shell).upload(files: [image], repository: "owner/repo")
                XCTFail("Expected invalid repository response")
            } catch {
                guard case .invalidResponse = error as? GitHubAttachmentUploadError else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            let calls = await shell.invocations
            XCTAssertEqual(calls.count, 2)
        }
    }
}
