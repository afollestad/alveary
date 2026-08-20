import Foundation
import XCTest

@testable import Alveary

final class GitHubDiffImageBlobFetcherTests: XCTestCase {
    private static let oid = "e908b5e52be4ecc4d05c38ad7afa27021fbb7472ff2d8eae58ae95fd0aca806a"

    override func tearDown() {
        StubURLProtocol.setResponder(nil)
        super.tearDown()
    }

    // MARK: - Ordinary blobs

    func testFetchesAnOrdinaryBlobFromTheRawHost() async throws {
        StubURLProtocol.setResponder { _ in
            StubURLProtocol.Stub(headers: ["Content-Length": "8"], body: stubImageBytes)
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        let data = try await fetcher.blob(
            for: gitHubBlobSource(storage: .blob(ref: "abc123")),
            maxBytes: 1024
        )

        XCTAssertEqual(data, stubImageBytes)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://raw.githubusercontent.com/octo/demo/abc123/assets/logo.png"
        )
        // `gh api` omits this header on non-API hosts, which is the whole reason this type exists.
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gho_test")
    }

    func testPercentEncodesPathSegmentsWithoutEscapingSeparators() async throws {
        StubURLProtocol.setResponder { _ in StubURLProtocol.Stub(body: stubImageBytes) }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        _ = try await fetcher.blob(
            for: gitHubBlobSource(path: "design assets/hero #1.png", storage: .blob(ref: "abc123")),
            maxBytes: 1024
        )

        XCTAssertEqual(
            StubURLProtocol.requests.first?.url?.absoluteString,
            "https://raw.githubusercontent.com/octo/demo/abc123/design%20assets/hero%20%231.png"
        )
    }

    // MARK: - Git LFS

    func testResolvesAnLFSObjectThroughTheBatchAPIThenDownloadsThePresignedHref() async throws {
        let href = "https://github-cloud.githubusercontent.com/alambic/media/1/e9/08/object"
        StubURLProtocol.setResponder { request in
            if request.url?.host == "github.com" {
                let json = """
                {"objects":[{"oid":"\(Self.oid)","size":8,"actions":{"download":{"href":"\(href)"}}}]}
                """
                return StubURLProtocol.Stub(body: Data(json.utf8))
            }
            return StubURLProtocol.Stub(headers: ["Content-Length": "8"], body: stubImageBytes)
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        let data = try await fetcher.blob(
            for: gitHubBlobSource(storage: .lfs(oid: Self.oid, byteSize: 8)),
            maxBytes: 1024
        )

        XCTAssertEqual(data, stubImageBytes)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.count, 2)

        let batch = try XCTUnwrap(requests.first)
        XCTAssertEqual(batch.url?.absoluteString, "https://github.com/octo/demo.git/info/lfs/objects/batch")
        XCTAssertEqual(batch.httpMethod, "POST")
        XCTAssertEqual(batch.value(forHTTPHeaderField: "Accept"), "application/vnd.git-lfs+json")
        // The LFS protocol authenticates with basic auth, not the bearer token the raw host takes.
        let expectedCredentials = Data("x-access-token:gho_test".utf8).base64EncodedString()
        XCTAssertEqual(batch.value(forHTTPHeaderField: "Authorization"), "Basic \(expectedCredentials)")

        let body = try XCTUnwrap(batch.httpBody)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(decoded["operation"] as? String, "download")
        let objects = try XCTUnwrap(decoded["objects"] as? [[String: Any]])
        XCTAssertEqual(objects.first?["oid"] as? String, Self.oid)
        XCTAssertEqual(objects.first?["size"] as? Int, 8)

        // The href is pre-signed; sending our credentials to it would be redundant.
        let download = requests[1]
        XCTAssertEqual(download.url?.absoluteString, href)
        XCTAssertNil(download.value(forHTTPHeaderField: "Authorization"))
    }

    func testSurfacesAnLFSObjectTheServerDoesNotHave() async {
        StubURLProtocol.setResponder { _ in
            let json = """
            {"objects":[{"oid":"\(Self.oid)","size":8,"error":{"code":404,"message":"Object does not exist"}}]}
            """
            return StubURLProtocol.Stub(body: Data(json.utf8))
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        do {
            _ = try await fetcher.blob(for: gitHubBlobSource(storage: .lfs(oid: Self.oid, byteSize: 8)), maxBytes: 1024)
            XCTFail("Expected the missing object to surface")
        } catch let error as GitHubDiffImageBlobFetcherError {
            XCTAssertEqual(error, .lfsObjectUnavailable(message: "Object does not exist"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Size gate

    func testRefusesAnOversizedLFSObjectWithoutIssuingAnyRequest() async {
        StubURLProtocol.setResponder { _ in StubURLProtocol.Stub(body: stubImageBytes) }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        do {
            _ = try await fetcher.blob(
                for: gitHubBlobSource(storage: .lfs(oid: Self.oid, byteSize: 5_000)),
                maxBytes: 1_000
            )
            XCTFail("Expected the pointer's own size to gate the fetch")
        } catch let error as DiffImageBlobTooLargeError {
            XCTAssertEqual(error.byteSize, 5_000)
        } catch {
            XCTFail("Unexpected error \(error)")
        }

        // The pointer already stated the size, so the gate costs no round trip at all.
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testBoundsTheTransferWithARangeRequestRatherThanStreamingBytes() async throws {
        StubURLProtocol.setResponder { _ in
            StubURLProtocol.Stub(statusCode: 206, headers: ["Content-Range": "bytes 0-7/8"], body: stubImageBytes)
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        let data = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1_000)

        XCTAssertEqual(data, stubImageBytes)
        // One byte past the limit, so an oversized blob is detectable without transferring it.
        XCTAssertEqual(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=0-1000")
    }

    func testRefusesAnOversizedBlobFromItsContentRangeWithoutTransferringIt() async {
        let truncated = Data(repeating: 0xAB, count: 1_001)
        StubURLProtocol.setResponder { _ in
            StubURLProtocol.Stub(
                statusCode: 206,
                headers: ["Content-Range": "bytes 0-1000/5000"],
                body: truncated
            )
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        do {
            _ = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1_000)
            XCTFail("Expected the declared total size to gate the fetch")
        } catch let error as DiffImageBlobTooLargeError {
            XCTAssertEqual(error.byteSize, 5_000, "Content-Range names the resource's true size")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// A server that ignores `Range` sends the whole body; the byte count still has to catch it.
    func testRefusesAnOversizedBlobWhenTheServerIgnoresTheRangeRequest() async {
        StubURLProtocol.setResponder { _ in
            StubURLProtocol.Stub(statusCode: 200, body: Data(repeating: 0xAB, count: 5_000))
        }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        do {
            _ = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1_000)
            XCTFail("Expected the transferred size to gate the fetch")
        } catch is DiffImageBlobTooLargeError {
            // Expected.
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testAcceptsAWholeBodyAnsweredWithoutPartialContent() async throws {
        StubURLProtocol.setResponder { _ in StubURLProtocol.Stub(statusCode: 200, body: stubImageBytes) }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        let data = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1_000)

        XCTAssertEqual(data, stubImageBytes)
    }

    // MARK: - Credentials

    func testRefreshesTheTokenOnceWhenGitHubRejectsTheCachedOne() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(
            ShellResult(stdout: "stale\n", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
        ))
        await shell.enqueue(.success(
            ShellResult(stdout: "fresh\n", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
        ))
        StubURLProtocol.setResponder { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer stale"
                ? StubURLProtocol.Stub(statusCode: 401)
                : StubURLProtocol.Stub(headers: ["Content-Length": "8"], body: stubImageBytes)
        }
        let fetcher = makeDiffImageBlobFetcher(shell: shell)

        let data = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1024)

        XCTAssertEqual(data, stubImageBytes)
        let tokenReads = await shell.invocations.filter { $0.args == ["auth", "token"] }
        XCTAssertEqual(tokenReads.count, 2, "A rejected token should be re-read exactly once")
    }

    func testReadsTheTokenOnceAcrossSequentialFetches() async throws {
        StubURLProtocol.setResponder { _ in
            StubURLProtocol.Stub(headers: ["Content-Length": "8"], body: stubImageBytes)
        }
        let shell = makeTokenShellRunner()
        let fetcher = makeDiffImageBlobFetcher(shell: shell)

        _ = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1024)
        _ = try await fetcher.blob(for: gitHubBlobSource(path: "b.png", storage: .blob(ref: "abc123")), maxBytes: 1024)

        let tokenReads = await shell.invocations.filter { $0.args == ["auth", "token"] }
        XCTAssertEqual(tokenReads.count, 1, "A diff full of images must not spawn one gh per image")
    }

    func testSurfacesANonAuthHTTPFailure() async {
        StubURLProtocol.setResponder { _ in StubURLProtocol.Stub(statusCode: 404) }
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())

        do {
            _ = try await fetcher.blob(for: gitHubBlobSource(storage: .blob(ref: "abc123")), maxBytes: 1024)
            XCTFail("Expected the 404 to surface")
        } catch let error as GitHubDiffImageBlobFetcherError {
            XCTAssertEqual(error, .httpStatus(404))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Source families

    func testRejectsACheckoutBackedSource() async {
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())
        do {
            _ = try await fetcher.blob(for: .git(.worktree(path: "a.png")), maxBytes: 1024)
            XCTFail("Expected a checkout source to be refused")
        } catch {
            XCTAssertEqual(error as? DiffImagePreviewLoaderError, .unsupportedSource)
        }
    }

    /// Remote bytes never already sit on disk, so opening one always materializes a temp file.
    func testNeverReportsAnExistingFileURL() {
        let fetcher = makeDiffImageBlobFetcher(shell: makeTokenShellRunner())
        XCTAssertNil(fetcher.existingFileURL(for: gitHubBlobSource(storage: .blob(ref: "abc123"))))
    }
}
