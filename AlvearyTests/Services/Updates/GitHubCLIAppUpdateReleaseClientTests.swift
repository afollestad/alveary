import XCTest

@testable import Alveary

final class GitHubCLIAppUpdateReleaseClientTests: XCTestCase {
    func testFetchesReleaseFeedWithGitHubCLI() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
        await shell.enqueue(.success(shellResult(stdout: "Logged in to github.com")))
        await shell.enqueue(.success(shellResult(stdout: "afollestad/alveary")))
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON())))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        let feed = try XCTUnwrap(result.installableFeed)
        let release = feed.latestRelease
        XCTAssertEqual(release.tagName, "v0.1.1")
        XCTAssertEqual(release.version.description, "0.1.1")
        XCTAssertEqual(release.changelogMarkdown, "## Changes")
        XCTAssertEqual(release.repositoryHTMLURL, URL(string: "https://github.com/afollestad/alveary"))
        XCTAssertEqual(release.asset.name, "Alveary.app.zip")
        XCTAssertEqual(release.asset.size, 456)
        XCTAssertEqual(release.asset.apiURL, URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123"))
        XCTAssertEqual(release.asset.downloadURL, URL(string: "https://github.com/afollestad/alveary/releases/download/v0.1.1/Alveary.app.zip"))
        XCTAssertEqual(release.asset.digest.gitHubDigest, validGitHubAssetDigest)
        XCTAssertEqual(feed.releaseNotes, [release.releaseNote])

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.executable), Array(repeating: "/opt/homebrew/bin/gh", count: 4))
        XCTAssertEqual(invocations[0].args, ["--version"])
        XCTAssertEqual(invocations[1].args, ["auth", "status"])
        XCTAssertEqual(
            invocations[2].args,
            ["repo", "view", "afollestad/alveary", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]
        )
        XCTAssertEqual(
            invocations[3].args,
            ["api", "--paginate", "--slurp", "repos/afollestad/alveary/releases?per_page=100"]
        )
        XCTAssertEqual(invocations[3].stdoutLimitBytes, 16 * 1024 * 1024)
    }

    func testFlattensPagesFiltersNonStableEntriesAndSortsSemanticVersions() async throws {
        let shell = await repositoryAccessibleShell()
        let pages = [
            [
                releaseResponse(tagName: "v0.1.2", body: "First 0.1.2"),
                releaseResponse(tagName: "v0.2.0", prerelease: true),
                releaseResponse(tagName: "nightly")
            ],
            [
                releaseResponse(tagName: "v0.1.10", body: "Newest"),
                releaseResponse(tagName: "0.1.2", body: "Duplicate 0.1.2"),
                releaseResponse(tagName: "v0.1.1", body: "Old notes", assetName: nil),
                releaseResponse(tagName: "v9.0.0", draft: true)
            ]
        ]
        await shell.enqueue(.success(shellResult(stdoutData: try releasePagesJSON(pages))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        let feed = try XCTUnwrap(result.installableFeed)
        XCTAssertEqual(feed.latestRelease.tagName, "v0.1.10")
        XCTAssertEqual(feed.releaseNotes.map(\.tagName), ["v0.1.10", "v0.1.2", "v0.1.1"])
        XCTAssertEqual(feed.releaseNotes.map(\.changelogMarkdown), ["Newest", "First 0.1.2", "Old notes"])
    }

    func testMissingGitHubCLIReturnsExplicitState() async {
        let shell = MockShellRunner()
        let client = makeClient(shell: shell, executablePath: nil)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.gitHubCLINotInstalled))
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testUnauthenticatedGitHubCLIReturnsExplicitState() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
        await shell.enqueue(.success(shellResult(stderr: "You are not logged into any GitHub hosts", exitCode: 1)))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.gitHubCLINotAuthenticated))
    }

    func testInaccessibleRepositoryReturnsExplicitState() async {
        let shell = await authenticatedShell()
        await shell.enqueue(
            .success(shellResult(stderr: "GraphQL: Could not resolve to a Repository with the name 'alveary'. (HTTP 404)", exitCode: 1))
        )
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.privateOrNotFound))
    }

    func testNoReleaseReturnsExplicitState() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try releasePagesJSON([[]]))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.noRelease))
    }

    func testReleaseRequestNotFoundReturnsExplicitState() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stderr: "gh: Not Found (HTTP 404)", exitCode: 1)))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.noRelease))
    }

    func testRateLimitReturnsExplicitState() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stderr: "gh: API rate limit exceeded (HTTP 403)", exitCode: 1)))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.rateLimited(resetDate: nil)))
    }

    func testDraftOnlyHistoryIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(draft: true))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.draftRelease))
    }

    func testPrereleaseOnlyHistoryIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(prerelease: true))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.prerelease))
    }

    func testMalformedStableHistoryIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(tagName: "nightly"))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.malformedVersion("nightly")))
    }

    func testMissingLatestAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(assetName: "Alveary.zip"))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.missingAsset(expectedName: "Alveary.app.zip")))
    }

    func testMissingLatestAssetDigestIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(digest: nil))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.missingAssetDigest(expectedName: "Alveary.app.zip")))
    }

    func testMalformedLatestAssetDigestIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(digest: "sha512:abc"))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.invalidAssetDigest("sha512:abc")))
    }

    func testNonHTTPSLatestAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(
            apiURL: "http://api.github.com/repos/afollestad/alveary/releases/assets/123"
        ))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.invalidAssetURL("http://api.github.com/repos/afollestad/alveary/releases/assets/123")))
    }

    func testNonHTTPSLatestBrowserDownloadAssetIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(downloadURL: "http://example.com/Alveary.app.zip"))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.invalidAssetURL("http://example.com/Alveary.app.zip")))
    }

    func testNonHTTPSLatestReleaseURLIsRejected() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdoutData: try singleReleaseJSON(
            htmlURL: "http://github.com/afollestad/alveary/releases/tag/v0.1.1"
        ))))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(
            result,
            .unavailable(.invalidReleaseURL("http://github.com/afollestad/alveary/releases/tag/v0.1.1"))
        )
    }

    func testTruncatedResponseIsExplicit() async throws {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(
            stdoutData: try singleReleaseJSON(),
            stdoutWasTruncated: true
        )))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        XCTAssertEqual(result, .unavailable(.decodingFailed("GitHub releases response exceeded the 16 MB limit.")))
    }

    func testDecodingFailureIsExplicit() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.success(shellResult(stdout: "{")))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        guard case .unavailable(.decodingFailed(let message)) = result else {
            XCTFail("Expected decoding failure, got \(result)")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testTransportFailureIsExplicit() async {
        let shell = await repositoryAccessibleShell()
        await shell.enqueue(.failure(.message("offline")))
        let client = makeClient(shell: shell)

        let result = await client.latestRelease()

        guard case .unavailable(.transportFailed(let message)) = result else {
            XCTFail("Expected transport failure, got \(result)")
            return
        }
        XCTAssertFalse(message.isEmpty)
    }
}

private extension AppUpdateReleaseLookupResult {
    var installableFeed: AppUpdateReleaseFeed? {
        guard case .installable(let feed) = self else {
            return nil
        }
        return feed
    }
}

private func makeClient(
    shell: MockShellRunner,
    executablePath: String? = "/opt/homebrew/bin/gh"
) -> GitHubCLIAppUpdateReleaseClient {
    GitHubCLIAppUpdateReleaseClient(
        shellRunner: shell,
        executableResolver: AppUpdateExecutablePathResolverFake(path: executablePath)
    )
}

private func authenticatedShell() async -> MockShellRunner {
    let shell = MockShellRunner()
    await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0")))
    await shell.enqueue(.success(shellResult(stdout: "Logged in to github.com")))
    return shell
}

private func repositoryAccessibleShell() async -> MockShellRunner {
    let shell = await authenticatedShell()
    await shell.enqueue(.success(shellResult(stdout: "afollestad/alveary")))
    return shell
}

private func shellResult(
    stdout: String = "",
    stdoutData: Data? = nil,
    stderr: String = "",
    exitCode: Int32 = 0,
    stdoutWasTruncated: Bool = false
) -> ShellResult {
    ShellResult(
        stdout: stdout,
        stdoutData: stdoutData,
        stderr: stderr,
        exitCode: exitCode,
        stdoutWasTruncated: stdoutWasTruncated,
        stderrWasTruncated: false
    )
}

private func singleReleaseJSON(
    tagName: String = "v0.1.1",
    body: String? = "## Changes",
    htmlURL: String? = nil,
    draft: Bool = false,
    prerelease: Bool = false,
    assetName: String? = "Alveary.app.zip",
    apiURL: String = "https://api.github.com/repos/afollestad/alveary/releases/assets/123",
    downloadURL: String? = nil,
    digest: String? = validGitHubAssetDigest
) throws -> Data {
    try releasePagesJSON([[
        releaseResponse(
            tagName: tagName,
            body: body,
            htmlURL: htmlURL,
            draft: draft,
            prerelease: prerelease,
            assetName: assetName,
            apiURL: apiURL,
            downloadURL: downloadURL,
            digest: digest
        )
    ]])
}

private func releasePagesJSON(_ pages: [[StubGitHubReleaseResponse]]) throws -> Data {
    try JSONEncoder().encode(pages)
}

private func releaseResponse(
    tagName: String,
    body: String? = "Changes",
    htmlURL: String? = nil,
    draft: Bool = false,
    prerelease: Bool = false,
    assetName: String? = "Alveary.app.zip",
    apiURL: String = "https://api.github.com/repos/afollestad/alveary/releases/assets/123",
    downloadURL: String? = nil,
    digest: String? = validGitHubAssetDigest
) -> StubGitHubReleaseResponse {
    let resolvedHTMLURL = htmlURL ?? "https://github.com/afollestad/alveary/releases/tag/\(tagName)"
    let resolvedDownloadURL = downloadURL ?? "https://github.com/afollestad/alveary/releases/download/\(tagName)/Alveary.app.zip"
    let assets: [StubGitHubReleaseAssetResponse]
    if let assetName {
        assets = [
            StubGitHubReleaseAssetResponse(
                name: assetName,
                url: apiURL,
                browserDownloadURL: resolvedDownloadURL,
                size: 456,
                digest: digest
            )
        ]
    } else {
        assets = []
    }
    return StubGitHubReleaseResponse(
        tagName: tagName,
        body: body,
        htmlURL: resolvedHTMLURL,
        draft: draft,
        prerelease: prerelease,
        assets: assets
    )
}

private struct StubGitHubReleaseResponse: Encodable {
    let tagName: String
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [StubGitHubReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct StubGitHubReleaseAssetResponse: Encodable {
    let name: String
    let url: String
    let browserDownloadURL: String
    let size: Int
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

private let validGitHubAssetDigest = "sha256:\(String(repeating: "a", count: 64))"

private struct AppUpdateExecutablePathResolverFake: ExecutablePathResolving {
    let path: String?

    func resolveExecutablePath(for candidate: String) async -> String? {
        XCTAssertEqual(candidate, "gh")
        return path
    }
}
